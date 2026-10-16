"""Private print documents and page previews; never contacts a printer."""
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from uuid import uuid4


def cache_root():
    root = Path(os.environ.get('XDG_CACHE_HOME') or Path.home()/'.cache')/'liquid-de/printing'
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    return root


def workspace(token,require_document=True):
    if not isinstance(token, str) or not re.fullmatch('[0-9a-f]{32}', token):
        raise ValueError('invalid-document-token')
    directory = cache_root()/token
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('unknown-document')
    manifest = directory/'manifest.json'
    if manifest.is_symlink():
        raise ValueError('invalid-document')
    data = json.loads(manifest.read_text())
    kinds=('liquid-print-document-1',) if require_document else ('liquid-print-document-1','liquid-print-preview-1')
    if data.get('kind') not in kinds:
        raise ValueError('invalid-document')
    document = directory/'document.pdf'
    if require_document and (document.is_symlink() or not document.is_file()):
        raise ValueError('invalid-document')
    return directory, data


def selected_pages(expression, count):
    if expression in (None, ''):
        return list(range(1, count+1))
    if not isinstance(expression, str) or len(expression) > 1024 or not re.fullmatch(r'[1-9][0-9]{0,5}(?:-[1-9][0-9]{0,5})?(?:,[1-9][0-9]{0,5}(?:-[1-9][0-9]{0,5})?)*', expression):
        raise ValueError('invalid-pages')
    output = set()
    for interval in expression.split(','):
        pair = list(map(int, interval.split('-')))
        start, end = pair[0], pair[-1]
        if not 1 <= start <= end <= count:
            raise ValueError('pages-out-of-range')
        output.update(range(start, end+1))
    return sorted(output)


def qt_application():
    os.environ['QT_QPA_PLATFORM'] = 'offscreen'
    from PySide6.QtGui import QGuiApplication
    return QGuiApplication.instance() or QGuiApplication(['liquid-print-document'])


def open_pdf(path):
    from PySide6.QtPdf import QPdfDocument
    pdf = QPdfDocument()
    if pdf.load(str(path)) != QPdfDocument.Error.None_ or not 1 <= pdf.pageCount() <= 20000:
        raise ValueError('unsupported-or-locked-pdf')
    return pdf


def prepare(source):
    if not isinstance(source, str) or not source or '\0' in source:
        raise ValueError('invalid-file')
    path = Path(source).expanduser().resolve(strict=True)
    if not path.is_file() or not os.access(path, os.R_OK) or path.stat().st_size > 512*1024*1024:
        raise ValueError('unreadable-or-large-file')
    extension = path.suffix.lower()
    if extension not in ('.pdf', '.png', '.jpg', '.jpeg', '.tif', '.tiff', '.bmp', '.webp', '.txt'):
        raise ValueError('unsupported-file')
    directory = cache_root()/uuid4().hex
    directory.mkdir(mode=0o700)
    output = directory/'document.pdf'
    try:
        if extension == '.pdf':
            shutil.copyfile(path, output)
        else:
            from PySide6.QtCore import QMarginsF, QRectF
            from PySide6.QtGui import QImageReader, QPageLayout, QPageSize, QPainter, QPdfWriter, QTextDocument
            writer = QPdfWriter(str(output))
            writer.setPageSize(QPageSize(QPageSize.PageSizeId.A4))
            writer.setPageMargins(QMarginsF(10,10,10,10), QPageLayout.Unit.Millimeter)
            writer.setResolution(144)
            writer.setTitle(path.name)
            if extension == '.txt':
                if path.stat().st_size > 5*1024*1024:
                    raise ValueError('text-too-large')
                text = QTextDocument()
                text.setPlainText(path.read_text(encoding='utf-8-sig'))
                text.print_(writer)
            else:
                reader = QImageReader(str(path))
                reader.setAutoTransform(True)
                # Some TIFF handlers lose the directory count if size() is
                # queried first. Count before inspecting the first frame.
                count = max(1,reader.imageCount())
                size = reader.size()
                if not size.isValid() or size.width()*size.height() > 100_000_000:
                    raise ValueError('invalid-or-large-image')
                if count > 20000:
                    raise ValueError('too-many-pages')
                painter = QPainter(writer)
                if not painter.isActive():
                    raise RuntimeError('pdf-writer-failed')
                for index in range(count):
                    if index:
                        if not reader.jumpToImage(index) or not writer.newPage():
                            raise RuntimeError('image-page-failed')
                    image = reader.read()
                    if image.isNull() or image.width()*image.height() > 100_000_000:
                        raise ValueError('invalid-image')
                    target = QRectF(0,0,writer.width(),writer.height())
                    ratio = min(target.width()/image.width(),target.height()/image.height())
                    w,h=image.width()*ratio,image.height()*ratio
                    painter.drawImage(QRectF((target.width()-w)/2,(target.height()-h)/2,w,h), image)
                painter.end()
            del writer
        pdf = open_pdf(output)
        first = pdf.pagePointSize(0)
        data = {'kind':'liquid-print-document-1', 'token':directory.name, 'name':path.name,
            'pageCount':pdf.pageCount(), 'widthPoints':first.width(), 'heightPoints':first.height()}
        pdf.close()
        os.chmod(output,0o600)
        (directory/'manifest.json').write_text(json.dumps(data))
        os.chmod(directory/'manifest.json',0o600)
        return data
    except Exception:
        shutil.rmtree(directory)
        raise


def preview(token, page, monochrome=False):
    directory, data = workspace(token)
    if type(page) is not int or not 1 <= page <= data['pageCount']:
        raise ValueError('pages-out-of-range')
    if type(monochrome) is not bool:
        raise ValueError('invalid-color')
    target = directory/('page-'+str(page)+('-gray' if monochrome else '')+'.png')
    if not target.exists():
        from PySide6.QtCore import QSize, Qt
        from PySide6.QtGui import QImage, QPainter
        pdf = open_pdf(directory/'document.pdf')
        size = pdf.pagePointSize(page-1)
        ratio = min(1100/size.width(),1100/size.height())
        rendered = pdf.render(page-1,QSize(max(1,int(size.width()*ratio)),max(1,int(size.height()*ratio))))
        if rendered.isNull():
            raise RuntimeError('preview-failed')
        # PDF pages may be transparent. Flatten on white paper before dropping
        # alpha for grayscale; otherwise transparent pixels turn solid black.
        image = QImage(rendered.size(),QImage.Format.Format_RGB32)
        image.fill(Qt.GlobalColor.white)
        painter = QPainter(image)
        painter.drawImage(0,0,rendered)
        painter.end()
        if monochrome:
            image = image.convertToFormat(QImage.Format.Format_Grayscale8)
        if not image.save(str(target),'PNG'):
            raise RuntimeError('preview-failed')
        os.chmod(target,0o600)
        pdf.close()
    return {'token':token,'page':page,'monochrome':monochrome,'url':target.as_uri()}


def number(value,low,high):
    if type(value) not in (int,float) or not math.isfinite(value) or not low<=value<=high:
        raise ValueError('invalid-page-edit')
    return value


def scan_preview(item):
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QImage,QImageReader,QPainter,QTransform
    if not isinstance(item,dict) or not isinstance(item.get('path'),str):raise ValueError('invalid-scan-pages')
    source=Path(item['path']).resolve(strict=True)
    if not source.is_file() or source.stat().st_size>512*1024*1024:raise ValueError('unreadable-or-large-file')
    reader=QImageReader(str(source));reader.setAutoTransform(True);size=reader.size()
    if not size.isValid() or size.width()*size.height()>100_000_000:raise ValueError('invalid-or-large-image')
    image=reader.read()
    if image.isNull():raise ValueError('invalid-image')
    dpi=number(item.get('dpi',image.dotsPerMeterX()*0.0254 or 300),1,9600)
    rotation=item.get('rotation',0)
    if type(rotation) is not int or rotation not in (0,90,180,270):raise ValueError('invalid-page-edit')
    if rotation:image=image.transformed(QTransform().rotate(rotation))
    crop=item.get('crop')
    if crop is not None:
        if not isinstance(crop,list) or len(crop)!=4:raise ValueError('invalid-page-edit')
        left,top,w,h=[number(value,0,1) for value in crop]
        if w<=0 or h<=0 or left+w>1.000001 or top+h>1.000001:raise ValueError('invalid-page-edit')
        image=image.copy(int(left*image.width()),int(top*image.height()),max(1,int(w*image.width())),max(1,int(h*image.height())))
    width_points=image.width()*72/dpi;height_points=image.height()*72/dpi
    effective_dpi=min(1,1100/max(image.width(),image.height()))*dpi
    image=image.scaled(1100,1100,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation) if max(image.width(),image.height())>1100 else image
    paper=QImage(image.size(),QImage.Format.Format_RGB32);paper.fill(Qt.GlobalColor.white)
    paper.setDotsPerMeterX(round(effective_dpi/0.0254));paper.setDotsPerMeterY(round(effective_dpi/0.0254))
    painter=QPainter(paper)
    try:
        painter.drawImage(0,0,image)
        paint_page_annotations(painter,item,paper.width(),paper.height(),effective_dpi)
    finally:painter.end()
    directory=cache_root()/uuid4().hex;directory.mkdir(mode=0o700)
    try:
        path=directory/'preview.png'
        if not paper.save(str(path),'PNG'):raise RuntimeError('preview-failed')
        os.chmod(path,0o600)
        data={'kind':'liquid-print-preview-1','token':directory.name,'url':path.as_uri(),
            'widthPoints':width_points,'heightPoints':height_points}
        (directory/'manifest.json').write_text(json.dumps(data));os.chmod(directory/'manifest.json',0o600)
        return data
    except Exception:shutil.rmtree(directory);raise


def paint_annotations(painter,items,width,height,resolution):
    from PySide6.QtCore import QPointF,QRectF,Qt
    from PySide6.QtGui import QBrush,QColor,QFont,QPen,QPolygonF
    if not isinstance(items,list) or len(items)>1000:raise ValueError('invalid-page-edit')
    for item in items:
        if not isinstance(item,dict):raise ValueError('invalid-page-edit')
        kind=item.get('kind');color=item.get('color','#E81123')
        if kind not in ('rectangle','ellipse','line','arrow','highlight','text','note') or not isinstance(color,str) or not re.fullmatch('#[0-9a-fA-F]{6}',color):
            raise ValueError('invalid-page-edit')
        x=number(item.get('x'),0,1)*width;y=number(item.get('y'),0,1)*height
        stroke=number(item.get('width',2),0.25,20)*resolution/72
        pen=QPen(QColor(color));pen.setWidthF(stroke);painter.setPen(pen);painter.setBrush(Qt.BrushStyle.NoBrush)
        if kind in ('line','arrow'):
            x2=number(item.get('x2'),0,1)*width;y2=number(item.get('y2'),0,1)*height
            painter.drawLine(QPointF(x,y),QPointF(x2,y2))
            if kind=='arrow':
                angle=math.atan2(y2-y,x2-x);length=max(8*resolution/72,stroke*4)
                points=[QPointF(x2,y2),QPointF(x2-length*math.cos(angle-0.45),y2-length*math.sin(angle-0.45)),QPointF(x2-length*math.cos(angle+0.45),y2-length*math.sin(angle+0.45))]
                painter.setBrush(QBrush(QColor(color)));painter.drawPolygon(QPolygonF(points))
            continue
        w=number(item.get('w'),0.000001,1)*width;h=number(item.get('h'),0.000001,1)*height
        if x+w>width+0.01 or y+h>height+0.01:raise ValueError('invalid-page-edit')
        rect=QRectF(x,y,w,h)
        if kind in ('highlight','note'):
            fill=QColor(color);fill.setAlphaF(0.3 if kind=='highlight' else 0.2)
            painter.fillRect(rect,fill)
        elif item.get('filled') is True:
            fill=QColor(color);fill.setAlphaF(number(item.get('opacity',0.25),0,1));painter.setBrush(fill)
        if kind=='ellipse':painter.drawEllipse(rect)
        elif kind in ('rectangle','note'):painter.drawRect(rect)
        if kind in ('text','note'):
            text=item.get('text','')
            if not isinstance(text,str) or len(text)>20000:raise ValueError('invalid-page-edit')
            font=QFont('Sans Serif');font.setPointSizeF(number(item.get('size',14),6,144));painter.setFont(font)
            rotation=item.get('rotation',0)
            if type(rotation) is not int or rotation not in (0,90,180,270):raise ValueError('invalid-page-edit')
            painter.save()
            if rotation:
                painter.translate(rect.center());painter.rotate(rotation)
                w,h=(rect.height(),rect.width()) if rotation in (90,270) else (rect.width(),rect.height())
                rect=QRectF(-w/2,-h/2,w,h)
            painter.drawText(rect,Qt.AlignmentFlag.AlignLeft|Qt.AlignmentFlag.AlignTop|Qt.TextFlag.TextWordWrap,text)
            painter.restore()


def paint_page_annotations(painter,item,width,height,resolution):
    from PySide6.QtCore import QRectF
    painter.save()
    try:
        painter.setClipRect(QRectF(0,0,width,height))
        crop=item.get('crop')
        if crop:
            left,top,w,h=crop
            painter.translate(-left*width/w,-top*height/h)
            width/=w;height/=h
        paint_annotations(painter,item.get('annotations',[]),width,height,resolution)
    finally:painter.restore()


def compose(pages,title='Documento scansionato.pdf'):
    from PySide6.QtCore import QMarginsF,QRectF,QSizeF
    from PySide6.QtGui import QImageReader,QPageLayout,QPageSize,QPainter,QPdfWriter,QTransform
    if not isinstance(pages,list) or not 1<=len(pages)<=1000:raise ValueError('invalid-scan-pages')
    if not isinstance(title,str) or not title or len(title)>255:raise ValueError('invalid-document-title')
    directory=cache_root()/uuid4().hex;directory.mkdir(mode=0o700);output=directory/'document.pdf'
    painter=None;writer=None
    try:
        writer=QPdfWriter(str(output));writer.setResolution(144);writer.setTitle(title)
        writer.setPageMargins(QMarginsF(0,0,0,0),QPageLayout.Unit.Millimeter)
        for index,item in enumerate(pages):
            if not isinstance(item,dict) or not isinstance(item.get('path'),str):raise ValueError('invalid-scan-pages')
            source=Path(item['path']).resolve(strict=True)
            if not source.is_file() or source.stat().st_size>512*1024*1024:raise ValueError('unreadable-or-large-file')
            reader=QImageReader(str(source));reader.setAutoTransform(True);size=reader.size()
            if not size.isValid() or size.width()*size.height()>100_000_000:raise ValueError('invalid-or-large-image')
            image=reader.read()
            if image.isNull():raise ValueError('invalid-image')
            dpi=number(item.get('dpi',image.dotsPerMeterX()*0.0254 or 300),1,9600)
            rotation=item.get('rotation',0)
            if type(rotation) is not int or rotation not in (0,90,180,270):raise ValueError('invalid-page-edit')
            if rotation:image=image.transformed(QTransform().rotate(rotation))
            crop=item.get('crop')
            if crop is not None:
                if not isinstance(crop,list) or len(crop)!=4:raise ValueError('invalid-page-edit')
                left,top,w,h=[number(v,0,1) for v in crop]
                if w<=0 or h<=0 or left+w>1.000001 or top+h>1.000001:raise ValueError('invalid-page-edit')
                image=image.copy(int(left*image.width()),int(top*image.height()),max(1,int(w*image.width())),max(1,int(h*image.height())))
            page_size=QPageSize(QSizeF(image.width()*25.4/dpi,image.height()*25.4/dpi),QPageSize.Unit.Millimeter)
            if not page_size.isValid():raise ValueError('invalid-scan-page-size')
            writer.setPageSize(page_size)
            if index:
                if not writer.newPage():raise RuntimeError('pdf-writer-failed')
            else:
                painter=QPainter(writer)
                if not painter.isActive():raise RuntimeError('pdf-writer-failed')
            painter.drawImage(QRectF(0,0,writer.width(),writer.height()),image)
            paint_page_annotations(painter,item,writer.width(),writer.height(),writer.resolution())
        painter.end();painter=None;del writer;writer=None
        pdf=open_pdf(output);first=pdf.pagePointSize(0)
        data={'kind':'liquid-print-document-1','token':directory.name,'name':title,'pageCount':pdf.pageCount(),
            'widthPoints':first.width(),'heightPoints':first.height()}
        pdf.close();os.chmod(output,0o600)
        (directory/'manifest.json').write_text(json.dumps(data));os.chmod(directory/'manifest.json',0o600)
        return data
    except Exception:
        if painter is not None:painter.end()
        writer=None;shutil.rmtree(directory);raise


def save(token,destination,overwrite=False):
    directory,data=workspace(token)
    if not isinstance(destination,str) or not destination or '\0' in destination or type(overwrite) is not bool:raise ValueError('invalid-output-file')
    path=Path(destination).expanduser().absolute()
    if path.suffix.lower()!='.pdf' or path.is_symlink():raise ValueError('invalid-output-file')
    parent=path.parent.resolve(strict=True);path=parent/path.name
    fd,temporary=tempfile.mkstemp(prefix='.liquid-pdf-',dir=parent)
    try:
        with os.fdopen(fd,'wb') as stream:
            with (directory/'document.pdf').open('rb') as source:shutil.copyfileobj(source,stream)
            stream.flush();os.fsync(stream.fileno())
        if overwrite:os.replace(temporary,path)
        else:
            try:os.link(temporary,path)
            except FileExistsError as error:raise ValueError('output-file-exists') from error
        return {'path':str(path),'token':token}
    finally:
        Path(temporary).unlink(missing_ok=True)


def main(request):
    action = request.get('action')
    if action == 'release':
        directory,_ = workspace(request.get('token'),require_document=False)
        shutil.rmtree(directory)
        return {}
    if action=='save':return save(request.get('token'),request.get('path'),request.get('overwrite',False))
    application = qt_application()
    if action=='scan-preview':return scan_preview(request.get('page'))
    if action=='compose':return compose(request.get('pages'),request.get('title','Documento scansionato.pdf'))
    if action == 'prepare':
        return prepare(request.get('file'))
    if action == 'preview':
        return preview(request.get('token'), request.get('page'), request.get('monochrome',False))
    raise ValueError('unknown-document-action')


if __name__ == '__main__':
    request = {}
    try:
        request = json.loads(sys.argv[1])
        if not isinstance(request,dict):
            request = {}
            raise ValueError('invalid-request')
        result = dict(main(request),ok=True)
    except ImportError:
        result = {'ok':False,'message':'print-document-support-missing'}
    except Exception as error:
        result = {'ok':False,'message':str(error)}
    result.update(action=request.get('action'),generation=request.get('generation'),revision=request.get('revision'))
    print(json.dumps(result,ensure_ascii=False))
