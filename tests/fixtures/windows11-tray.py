#!/usr/bin/env python3
"""Real private StatusNotifierItem + DBusMenu fixture; never user bus."""
import json, os, sys
from pathlib import Path
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
assert os.environ.get('LIQUID_TEST_BUS')=='1'
DBusGMainLoop(set_as_default=True)
bus=dbus.SessionBus();output=Path(sys.argv[1]);events=[];objects=[]
def record(action):
 events.append(action);output.write_text(json.dumps(events))
class Item(dbus.service.Object):
 def __init__(self,index):
  self.index=index;self.private_bus=dbus.SessionBus(private=True);self.name=dbus.service.BusName('org.liquid.TestTray'+str(index),self.private_bus)
  super().__init__(self.name,'/StatusNotifierItem')
 @dbus.service.method('org.freedesktop.DBus.Properties',in_signature='s',out_signature='a{sv}')
 def GetAll(self,interface):
  return {'Category':'ApplicationStatus','Id':'test'+str(self.index),'Title':'Demo '+str(self.index),'Status':'Active','WindowId':dbus.UInt32(0),'IconName':'','IconPixmap':dbus.Array([dbus.Struct((20,20,dbus.ByteArray(bytes([255,0,103,192])*400)),signature='iiay')],signature='(iiay)'), 'Menu':dbus.ObjectPath('/Menu'),'ItemIsMenu':False,'ToolTip':dbus.Struct(('',dbus.Array([],signature='(iiay)'),'Demo '+str(self.index),'Icona di prova'),signature='sa(iiay)ss')}
 @dbus.service.method('org.freedesktop.DBus.Properties',in_signature='ss',out_signature='v')
 def Get(self,interface,name):return self.GetAll(interface)[name]
 @dbus.service.method('org.kde.StatusNotifierItem',in_signature='ii')
 def Activate(self,x,y):record('activate-'+str(self.index))
 @dbus.service.method('org.kde.StatusNotifierItem',in_signature='ii')
 def SecondaryActivate(self,x,y):record('secondary-'+str(self.index))
 @dbus.service.method('org.kde.StatusNotifierItem',in_signature='ii')
 def ContextMenu(self,x,y):record('context-'+str(self.index))
class Menu(dbus.service.Object):
 def __init__(self,item):super().__init__(item.name,'/Menu')
 @dbus.service.method('org.freedesktop.DBus.Properties',in_signature='s',out_signature='a{sv}')
 def GetAll(self,interface):return {'Version':dbus.UInt32(3),'TextDirection':'ltr','Status':'normal','IconThemePath':dbus.Array([],signature='s')}
 @dbus.service.method('com.canonical.dbusmenu',in_signature='iias',out_signature='u(ia{sv}av)')
 def GetLayout(self,parent,depth,names):
  children=dbus.Array([dbus.Struct((n,dbus.Dictionary({'label':label,'enabled':enabled,'visible':True},signature='sv'),dbus.Array([],signature='v')),signature='ia{sv}av',variant_level=1) for n,label,enabled in [(1,'Apri',True),(2,'Disabilitato',False)]],signature='v')
  return dbus.UInt32(1),dbus.Struct((0,dbus.Dictionary({'children-display':'submenu'},signature='sv'),children),signature='ia{sv}av')
 @dbus.service.method('com.canonical.dbusmenu',in_signature='ias',out_signature='a(ia{sv})')
 def GetGroupProperties(self,ids,names):return dbus.Array([],signature='(ia{sv})')
 @dbus.service.method('com.canonical.dbusmenu',in_signature='i',out_signature='b')
 def AboutToShow(self,id):return False
 @dbus.service.method('com.canonical.dbusmenu',in_signature='isvu')
 def Event(self,id,event,value,time):record('menu-'+str(id)+'-'+event)
watcher=dbus.Interface(bus.get_object('org.kde.StatusNotifierWatcher','/StatusNotifierWatcher'),'org.kde.StatusNotifierWatcher')
for i in range(9):
 item=Item(i);objects.extend([item,Menu(item)]);watcher.RegisterStatusNotifierItem(item.name.get_name())
print('READY',flush=True);GLib.MainLoop().run()
