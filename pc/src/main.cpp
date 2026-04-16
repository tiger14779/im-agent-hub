#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <QDir>
#include <QLibraryInfo>
#include <QFile>
#include <QDateTime>
#include <QMutex>
#include <QSharedMemory>
#include <QLocalServer>
#include <QLocalSocket>
#include <QWindow>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QStandardPaths>

// 全局日志文件，将 qDebug 输出重定向到文件
static QFile *g_logFile = nullptr;
static QMutex g_logMutex;

void fileMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    Q_UNUSED(ctx)
    QMutexLocker locker(&g_logMutex);
    if (!g_logFile || !g_logFile->isOpen())
        return;
    const char *level = "DEBUG";
    switch (type) {
    case QtWarningMsg:  level = "WARN";  break;
    case QtCriticalMsg: level = "CRIT";  break;
    case QtFatalMsg:    level = "FATAL"; break;
    default: break;
    }
    QString line = QStringLiteral("%1 [%2] %3\n")
                       .arg(QDateTime::currentDateTime().toString("hh:mm:ss.zzz"), level, msg);
    g_logFile->write(line.toUtf8());
    g_logFile->flush();
}

static const char *kAppKey = "ImAgentHub_SingleInstance_Key";
static const char *kServerName = "ImAgentHub_LocalServer";

// QML 引擎网络访问管理工厂 —— 为所有 Image 组件提供 HTTP 磁盘缓存
// 切换会话后图片/头像从本地缓存秒显，不再每次重新下载
class CachedNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        auto *nam = new QNetworkAccessManager(parent);
        auto *diskCache = new QNetworkDiskCache(nam);
        QString cacheDir = QStandardPaths::writableLocation(
                               QStandardPaths::CacheLocation) + "/img_cache";
        diskCache->setCacheDirectory(cacheDir);
        diskCache->setMaximumCacheSize(300LL * 1024 * 1024); // 300 MB 上限
        nam->setCache(diskCache);
        qDebug() << "[CachedNam] 磁盘缓存目录:" << cacheDir;
        return nam;
    }
};

// 尝试通知已有实例显示窗口，成功返回 true（说明已有实例在运行）
static bool notifyRunningInstance()
{
    QLocalSocket socket;
    socket.connectToServer(kServerName);
    if (socket.waitForConnected(500)) {
        socket.write("show");
        socket.waitForBytesWritten(500);
        socket.disconnectFromServer();
        return true;
    }
    return false;
}

// 将所有窗口提到前台显示
static void raiseAllWindows()
{
    const auto windows = QGuiApplication::allWindows();
    for (QWindow *w : windows) {
        if (w->isVisible()) {
            w->showNormal();
            w->raise();
            w->requestActivate();
        }
    }
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("IM Agent Hub");
    app.setOrganizationName("ImAgentHub");
    app.setApplicationVersion("1.0.0");

    // ── 单实例互斥检测 ──
    QSharedMemory sharedMem(kAppKey);
    if (!sharedMem.create(1)) {
        // 共享内存已存在 → 已有实例在运行，通知它显示窗口后退出
        if (notifyRunningInstance()) {
            qDebug() << "已有实例在运行，通知其显示窗口后退出";
            return 0;
        }
        // 若通知失败（可能上次异常退出残留共享内存），清理后继续
        sharedMem.attach();
        sharedMem.detach();
        sharedMem.create(1);
    }

    // ── 本地服务器：接收第二个实例的 "show" 消息 ──
    QLocalServer::removeServer(kServerName);
    QLocalServer localServer;
    localServer.listen(kServerName);
    QObject::connect(&localServer, &QLocalServer::newConnection, [&localServer]() {
        QLocalSocket *client = localServer.nextPendingConnection();
        if (!client) return;
        QObject::connect(client, &QLocalSocket::readyRead, [client]() {
            QByteArray data = client->readAll();
            if (data == "show") {
                raiseAllWindows();
            }
            client->deleteLater();
        });
    });

    // 将 qDebug 输出重定向到与 exe 同目录的日志文件
    g_logFile = new QFile(QCoreApplication::applicationDirPath() + "/pc_debug.log");
    g_logFile->open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text);
    qInstallMessageHandler(fileMessageHandler);

    qDebug() << "启动 IM Agent Hub PC 客户端...";

    QQuickStyle::setStyle("Basic");

    // 图片磁盘缓存（300MB）：QML Image 加载 HTTP 资源时自动命中缓存，切换会话不再重新下载
    CachedNamFactory namFactory;
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(&namFactory);

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
