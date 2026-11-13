#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <QtQml/qqmlregistration.h>

class NoteHighlighter : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument* document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)
public:
    explicit NoteHighlighter(QObject* parent=nullptr):QObject(parent){}
    QQuickTextDocument* document() const {return m_document;}
    bool dark() const {return m_dark;}
    void setDocument(QQuickTextDocument*);
    void setDark(bool);
signals:
    void changed();
private:
    QPointer<QQuickTextDocument> m_document;
    QPointer<QSyntaxHighlighter> m_highlighter;
    bool m_dark=true;
};
