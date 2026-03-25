#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <QDir>
#include <QLibraryInfo>

/**
 * @brief 程序入口
 *
 * 初始化顺序：
 *   1. 创建 QGuiApplication 并设置应用信息
 *   2. 设置 QML 样式为 "Basic"
 *   3. 创建 QML 引擎并加载主窗口模块
 *   4. 进入事件循环
 */
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("IM Agent Hub");
    app.setOrganizationName("ImAgentHub");
    app.setApplicationVersion("1.0.0");

    qDebug() << "启动 IM Agent Hub PC 客户端...";

    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;

    // 确保 QML 引擎能找到 Qt 自带的 QML 模块（如 QtMultimedia）
    // 从 build 目录运行时，QLibraryInfo 路径是相对于 exe 的，
    // 所以通过 CMake 定义注入实际的 Qt SDK qml 路径
#ifdef QT_QML_IMPORT_DIR
    engine.addImportPath(QStringLiteral(QT_QML_IMPORT_DIR));
#endif
    qDebug() << "QML 导入路径:" << engine.importPathList();

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() {
            qCritical() << "QML 对象创建失败!";
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [](QObject *obj, const QUrl &url) {
            if (obj)
                qDebug() << "QML 加载成功:" << url;
            else
                qCritical() << "QML 对象为空:" << url;
        },
        Qt::QueuedConnection);

    qDebug() << "加载 QML 模块 ImAgentHub::Main...";
    engine.loadFromModule("ImAgentHub", "Main");
    qDebug() << "QML 模块加载完成，进入事件循环...";

    return app.exec();
}
