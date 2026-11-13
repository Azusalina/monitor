#include "notehighlighter.h"
#include <KSyntaxHighlighting/AbstractHighlighter>
#include <KSyntaxHighlighting/Repository>
#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Format>
#include <KSyntaxHighlighting/State>
#include <KSyntaxHighlighting/Theme>
#include <QTextBlock>
#include <QTextCharFormat>
#include <QHash>
namespace {
KSyntaxHighlighting::Repository& repository() {static KSyntaxHighlighting::Repository repo;return repo;}
struct CodeState : QTextBlockUserData {KSyntaxHighlighting::State state;QString language;};
class CodeHighlighter : public QSyntaxHighlighter, public KSyntaxHighlighting::AbstractHighlighter {
public:
    explicit CodeHighlighter(QTextDocument* doc):QSyntaxHighlighter(doc){}
protected:
    void highlightBlock(const QString& text) override {
        const QString language=currentBlock().blockFormat().stringProperty(QTextFormat::BlockCodeLanguage).toLower();
        if(language.isEmpty()) {setCurrentBlockUserData(nullptr);return;}
        static const QHash<QString,QString> aliases={{"py","Python"},{"python","Python"},{"js","JavaScript"},{"javascript","JavaScript"},{"ts","TypeScript"},{"cpp","C++"},{"c++","C++"},{"sh","Bash"},{"bash","Bash"},{"shell","Bash"}};
        auto definition=repository().definitionForName(aliases.value(language,language));
        if(!definition.isValid()) {
            for(const auto& candidate:repository().definitions()) if(candidate.name().toLower()==language){definition=candidate;break;}
        }
        if(!definition.isValid()) definition=repository().definitionForFileName("note."+language);
        setDefinition(definition);
        auto previous=dynamic_cast<CodeState*>(currentBlock().previous().userData());
        auto state=new CodeState;
        state->language=language;
        state->state=highlightLine(text,previous && previous->language==language ? previous->state : KSyntaxHighlighting::State());
        setCurrentBlockUserData(state);
    }
    void applyFormat(int offset,int length,const KSyntaxHighlighting::Format& format) override {
        QTextCharFormat style;
        const auto color=format.textColor(theme());
        if(color.isValid()) style.setForeground(color);
        if(format.isBold(theme())) style.setFontWeight(QFont::Bold);
        if(format.isItalic(theme())) style.setFontItalic(true);
        setFormat(offset,length,style);
    }
};
}
void NoteHighlighter::setDocument(QQuickTextDocument* value) {
    if(m_document==value)return;
    delete m_highlighter.data();m_document=value;
    if(value) {
        auto highlighter=new CodeHighlighter(value->textDocument());
        highlighter->setTheme(repository().defaultTheme(m_dark?KSyntaxHighlighting::Repository::DarkTheme:KSyntaxHighlighting::Repository::LightTheme));
        highlighter->rehighlight();m_highlighter=highlighter;
    }
    emit changed();
}
void NoteHighlighter::setDark(bool value) {
    if(m_dark==value)return;m_dark=value;
    if(auto highlighter=dynamic_cast<CodeHighlighter*>(m_highlighter.data())) {
        highlighter->setTheme(repository().defaultTheme(value?KSyntaxHighlighting::Repository::DarkTheme:KSyntaxHighlighting::Repository::LightTheme));
        highlighter->rehighlight();
    }
    emit changed();
}
