#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <QDir>
#include <QLibraryInfo>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("IM Agent Hub");
    app.setOrganizationName("ImAgentHub");
    app.setApplicationVersion("1.0.0");

    qDebug() << "Starting IM Agent Hub PC...";

    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;

    // Ensure QML engine can find Qt's own QML modules (e.g. QtMultimedia)
    // When running from build dir, QLibraryInfo paths are relative to exe,
    // so we inject the real Qt SDK qml path via CMake define
#ifdef QT_QML_IMPORT_DIR
    engine.addImportPath(QStringLiteral(QT_QML_IMPORT_DIR));
#endif
    qDebug() << "All import paths:" << engine.importPathList();

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() {
            qCritical() << "QML object creation FAILED!";
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [](QObject *obj, const QUrl &url) {
            if (obj)
                qDebug() << "QML loaded OK:" << url;
            else
                qCritical() << "QML object is null for:" << url;
        },
        Qt::QueuedConnection);

    qDebug() << "Loading QML module ImAgentHub::Main...";
    engine.loadFromModule("ImAgentHub", "Main");
    qDebug() << "QML module loaded, entering event loop...";

    return app.exec();
}
