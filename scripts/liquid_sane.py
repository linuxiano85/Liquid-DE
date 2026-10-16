"""Linux SANE v1 ABI: structured discovery and option descriptors.

API reference: https://sane-project.gitlab.io/standard/api.html
No acquisition is started by this module.
"""
import ctypes as C
from ctypes.util import find_library
import math


class Device(C.Structure):
    _fields_=[('name',C.c_char_p),('vendor',C.c_char_p),('model',C.c_char_p),('type',C.c_char_p)]


class Range(C.Structure):
    _fields_=[('min',C.c_int),('max',C.c_int),('quant',C.c_int)]


class Constraint(C.Union):
    _fields_=[('strings',C.POINTER(C.c_char_p)),('words',C.POINTER(C.c_int)),('range',C.POINTER(Range))]


class Option(C.Structure):
    _fields_=[('name',C.c_char_p),('title',C.c_char_p),('description',C.c_char_p),
        ('type',C.c_int),('unit',C.c_int),('size',C.c_int),('cap',C.c_int),
        ('constraint_type',C.c_int),('constraint',Constraint)]


class SaneError(RuntimeError):
    def __init__(self,status):
        self.status=status
        super().__init__('sane-status-'+str(status))


def text(value):
    if value is None:return ''
    try:return value.decode('utf-8')
    except UnicodeDecodeError:return value.decode('latin-1')


def check(status):
    if status:raise SaneError(status)


class Sane:
    def __init__(self):
        if C.sizeof(C.c_int)!=4:raise RuntimeError('unsupported-sane-abi')
        path=find_library('sane')
        if not path:raise RuntimeError('sane-support-missing')
        self.lib=C.CDLL(path)
        for name,args,result in [
            ('sane_init',[C.POINTER(C.c_int),C.c_void_p],C.c_int),
            ('sane_exit',[],None),
            ('sane_get_devices',[C.POINTER(C.POINTER(C.POINTER(Device))),C.c_int],C.c_int),
            ('sane_open',[C.c_char_p,C.POINTER(C.c_void_p)],C.c_int),
            ('sane_close',[C.c_void_p],None),
            ('sane_get_option_descriptor',[C.c_void_p,C.c_int],C.POINTER(Option)),
            ('sane_control_option',[C.c_void_p,C.c_int,C.c_int,C.c_void_p,C.POINTER(C.c_int)],C.c_int)]:
            function=getattr(self.lib,name);function.argtypes=args;function.restype=result
        version=C.c_int()
        check(self.lib.sane_init(C.byref(version),None))
        if (version.value>>24)!=1:
            self.lib.sane_exit();raise RuntimeError('unsupported-sane-version')
        self.handle=C.c_void_p()

    def __enter__(self):return self
    def __exit__(self,*error):
        if self.handle:self.lib.sane_close(self.handle)
        self.lib.sane_exit()

    def devices(self):
        devices=C.POINTER(C.POINTER(Device))()
        check(self.lib.sane_get_devices(C.byref(devices),0))
        rows=[]
        if not devices:return rows
        for index in range(4096):
            if not devices[index]:break
            row=devices[index].contents
            rows.append({key:text(getattr(row,key)) for key in ('name','vendor','model','type')})
        return rows

    def open(self,name):
        if not isinstance(name,str) or not name or '\0' in name or len(name)>4096:
            raise ValueError('invalid-scanner')
        if name not in {device['name'] for device in self.devices()}:
            raise ValueError('scanner-no-longer-discovered')
        check(self.lib.sane_open(name.encode(),C.byref(self.handle)))

    def descriptor(self,index):
        pointer=self.lib.sane_get_option_descriptor(self.handle,index)
        if not pointer:raise ValueError('unknown-scan-option')
        return pointer.contents

    def count(self):
        count=C.c_int();info=C.c_int()
        check(self.lib.sane_control_option(self.handle,0,0,C.byref(count),C.byref(info)))
        if not 1<=count.value<=4096:raise RuntimeError('invalid-sane-option-count')
        return count.value

    def value(self,index,descriptor):
        if descriptor.size<=0 or descriptor.size>1024*1024 or descriptor.type not in (0,1,2,3):return None
        buffer=C.create_string_buffer(descriptor.size);info=C.c_int()
        status=self.lib.sane_control_option(self.handle,index,0,buffer,C.byref(info))
        if status:return None
        if descriptor.type==3:return text(buffer.value)
        if descriptor.size%4:return None
        words=C.cast(buffer,C.POINTER(C.c_int))
        result=[words[i]/65536 if descriptor.type==2 else words[i] for i in range(descriptor.size//4)]
        return result[0] if len(result)==1 else result

    def options(self):
        rows=[]
        for index in range(1,self.count()):
            descriptor=self.descriptor(index)
            row={'index':index,'name':text(descriptor.name),'title':text(descriptor.title),
                'description':text(descriptor.description),'type':descriptor.type,'unit':descriptor.unit,
                'active':not bool(descriptor.cap&32),'settable':bool(descriptor.cap&1),
                'advanced':bool(descriptor.cap&64),'choices':[]}
            if descriptor.constraint_type==3 and descriptor.constraint.strings:
                for n in range(4096):
                    value=descriptor.constraint.strings[n]
                    if value is None:break
                    row['choices'].append(text(value))
            elif descriptor.constraint_type==2 and descriptor.constraint.words:
                count=descriptor.constraint.words[0]
                if not 0<=count<=4096:raise RuntimeError('invalid-sane-constraint')
                row['choices']=[descriptor.constraint.words[n+1]/65536 if descriptor.type==2 else descriptor.constraint.words[n+1] for n in range(count)]
            elif descriptor.constraint_type==1 and descriptor.constraint.range:
                limits=descriptor.constraint.range.contents
                row['range']={key:getattr(limits,key)/65536 if descriptor.type==2 else getattr(limits,key) for key in ('min','max','quant')}
            row['value']=self.value(index,descriptor) if row['active'] and descriptor.cap&4 else None
            rows.append(row)
        return rows

    def select(self,name,value):
        rows=self.options()
        option=next((row for row in rows if row['name']==name),None)
        if not option or not option['active'] or not option['settable']:
            raise ValueError('unsupported-scan-option')
        if option['choices'] and value not in option['choices']:
            raise ValueError('unsupported-scan-value')
        if option['type']==3:
            if not isinstance(value,str) or '\0' in value:raise ValueError('unsupported-scan-value')
            encoded=value.encode()
            size=self.descriptor(option['index']).size
            if len(encoded)>=size:raise ValueError('unsupported-scan-value')
            buffer=C.create_string_buffer(encoded,size)
        elif option['type'] in (0,1,2):
            if type(value) not in (int,float) or not math.isfinite(value):raise ValueError('unsupported-scan-value')
            if option['type'] in (0,1) and value!=round(value):raise ValueError('unsupported-scan-value')
            if 'range' in option and not option['range']['min']<=value<=option['range']['max']:
                raise ValueError('unsupported-scan-value')
            wire=round(value*65536) if option['type']==2 else round(value)
            if not -(2**31)<=wire<2**31:raise ValueError('unsupported-scan-value')
            buffer=C.c_int(wire)
        else:raise ValueError('unsupported-scan-option')
        info=C.c_int()
        check(self.lib.sane_control_option(self.handle,option['index'],1,C.byref(buffer),C.byref(info)))
        # Source/mode may reload descriptors and invalidate all old pointers.
        current=next((row for row in self.options() if row['name']==name),None)
        return current['value'] if current else None


def capabilities(device,selections=None):
    selections={} if selections is None else selections
    if not isinstance(selections,dict) or selections.keys()-{'source','mode','resolution','depth','tl-x','tl-y','br-x','br-y'}:
        raise ValueError('unsupported-scan-option')
    with Sane() as sane:
        sane.open(device)
        applied={}
        # Source and mode must be applied before numeric constraints are read.
        for name in ('source','mode','resolution','depth','tl-x','tl-y','br-x','br-y'):
            if name in selections:applied[name]=sane.select(name,selections[name])
        return {'device':device,'options':sane.options(),'applied':applied}
