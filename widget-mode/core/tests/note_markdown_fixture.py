"""Inspect real Qt Markdown layout and native KDE syntax ranges in memory."""
import os
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from pathlib import Path
from PySide6.QtCore import QObject,QUrl,QMetaObject,Qt,QPoint
from PySide6.QtGui import QFontDatabase,QTextFormat,QColor
from PySide6.QtQuick import QQuickView
from PySide6.QtWidgets import QApplication
from PySide6.QtTest import QTest
app=QApplication([]);view=QQuickView();view.setColor(QColor(Qt.GlobalColor.transparent));warnings=[]
view.engine().warnings.connect(lambda errors:warnings.extend(str(e) for e in errors))
view.setSource(QUrl.fromLocalFile(str(Path(__file__).with_name('NoteMarkdownFixture.qml'))));assert view.rootObject();view.show();QTest.qWait(200)
root=view.rootObject();card=root.findChild(QObject,'markdownCard');prefs=root.findChild(QObject,'markdownPreferences');rendered=root.findChild(QObject,'noteRendered');editor=root.findChild(QObject,'noteEditor')
source=prefs.property('noteText');assert rendered.property('visible') and not editor.property('visible')
quick_document=rendered.property('textDocument')
doc=quick_document.textDocument()
assert 'Heading' in doc.toPlainText() and '# Heading' not in doc.toPlainText()
assert '```' not in doc.toPlainText() and 'def answer():' in doc.toPlainText()
b=doc.begin();code=[]
while b.isValid():
 if b.blockFormat().stringProperty(QTextFormat.Property.BlockCodeLanguage)=='python':code.append(b)
 b=b.next()
assert len(code)==2
assert any(any(r.format.hasProperty(QTextFormat.Property.ForegroundBrush) for r in b.layout().formats()) for b in code),'Expected actual syntax color ranges'
assert rendered.property('font').pixelSize()==16
families=QFontDatabase.families();assert families
family=next((f for f in families if 'sans' in f.lower()),families[0]);prefs.setProperty('noteFontFamily',family);prefs.setProperty('noteFontSize',22);QTest.qWait(50)
assert rendered.property('font').pixelSize()==22 and editor.property('font').pixelSize()==22
styles=QFontDatabase.styles(family)
if styles:
 prefs.setProperty('noteFontStyle',styles[0]);QTest.qWait(30);assert editor.property('font').styleName()==styles[0]
QMetaObject.invokeMethod(card,'beginEdit');QTest.qWait(30);assert editor.property('visible') and editor.property('activeFocus')
editor.setProperty('text',source+'\n\n## Saved update');QTest.keyClick(view,Qt.Key.Key_Escape);QTest.qWait(100)
assert prefs.property('noteText').endswith('## Saved update') and rendered.property('visible')
card.setProperty('covered',True);QTest.qWait(250);assert not rendered.property('visible');assert prefs.property('noteText').endswith('## Saved update')
card.setProperty('covered',False);prefs.setProperty('noteMarkdown',False);QTest.qWait(50);assert editor.property('visible') and editor.property('text')==prefs.property('noteText')
prefs.setProperty('noteMarkdown',True);QTest.qWait(250);root.findChild(QObject,'noteViewport').setProperty('contentY',0);QTest.qWait(30);view.grabWindow().save(str(Path(__file__).parents[2]/'docs/note-markdown-preview.png'))
assert not warnings,'\n'.join(warnings)
print('Markdown block rendering, real fenced-code syntax colors, installed font changes, size, raw-source persistence, Escape, curtain and plain-text fallback passed.')
view.close()
