"""Private print documents and page previews; never contacts a printer."""
import json
import os
from pathlib import Path
import re
import shutil
import sys
from uuid import uuid4


def cache_root():
    root = Path(os.environ.get('XDG_CACHE_HOME') or Path.home()/'.cache')/'liquid-de/printing'
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    return root


def workspace(token):
    if not isinstance(token, str) or not re.fullmatch('[0-9a-f]{32}', token):
        raise ValueError('invalid-document-token')
    directory = cache_root()/token
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('unknown-document')
    manifest = directory/'manifest.json'
    if manifest.is_symlink():
        raise ValueError('invalid-document')
    data = json.loads(manifest.read_text())
    if data.get('kind') != 'liquid-print-document-1':
        raise ValueError('invalid-document')
    document = directory/'document.pdf'
    if document.is_symlink() or not document.is_file():
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


def main(request):
    action = request.get('action')
    if action == 'release':
        directory,_ = workspace(request.get('token'))
        shutil.rmtree(directory)
        return {}
    application = qt_application()
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
    result.update(action=request.get('action'),generation=request.get('generation'))
    print(json.dumps(result,ensure_ascii=False))
