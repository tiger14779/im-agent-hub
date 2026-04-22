#include "avatarprovider.h"

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkDiskCache>
#include <QStandardPaths>
#include <QImageReader>
#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QDebug>
#include <QtConcurrent>
#include <QThread>

// ───────── AvatarResponse ─────────
QQuickTextureFactory *AvatarResponse::textureFactory() const
{
    if (m_image.isNull())
        return nullptr;
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

void AvatarResponse::setImage(const QImage &img)
{
    m_image = img;
    emit finished();
}

void AvatarResponse::setError(const QString &err)
{
    m_error = err;
    emit finished();
}

// ───────── AvatarProvider ─────────
AvatarProvider::AvatarProvider()
    : QQuickAsyncImageProvider()
    , m_cache(500)
{
    m_nam = new QNetworkAccessManager();
    auto *disk = new QNetworkDiskCache(m_nam);    QString cacheDir = QStandardPaths::writableLocation(
                           QStandardPaths::CacheLocation) + "/avatar_cache";
    disk->setCacheDirectory(cacheDir);
    disk->setMaximumCacheSize(200LL * 1024 * 1024);
    m_nam->setCache(disk);
    qDebug() << "[AvatarProvider] 磁盘缓存目录:" << cacheDir
             << "内存 LRU 容量:" << m_cache.maxCost();
}

void AvatarProvider::setCacheCapacity(int n)
{
    QMutexLocker lock(&m_mutex);
    m_cache.setMaxCost(n);
}

QQuickImageResponse *AvatarProvider::requestImageResponse(const QString &id,
                                                          const QSize &requestedSize)
{
    auto *resp = new AvatarResponse();

    // 1) 命中内存 LRU → 立即返回
    {
        QMutexLocker lock(&m_mutex);
        if (auto *cached = m_cache.object(id)) {
            QImage copy = *cached;       // 拷贝一份给响应（QImage 隐式共享，开销极低）
            // finished 必须在 QML 线程上发，而 requestImageResponse 本身在 QML 线程
            QMetaObject::invokeMethod(resp, [resp, copy]() {
                resp->setImage(copy);
            }, Qt::QueuedConnection);
            return resp;
        }
    }

    // 2) 未命中 → 在 NAM 所在线程（主线程）发起请求
    //    Qt 网络栈本身是异步的，不会阻塞 UI
    QString url = id;
    int targetW = requestedSize.width()  > 0 ? requestedSize.width()  : 80;
    int targetH = requestedSize.height() > 0 ? requestedSize.height() : 80;

    QMetaObject::invokeMethod(this, [this, resp, url, targetW, targetH]() {
        // 本地文件直接读取
        if (url.startsWith(QStringLiteral("file:///")) ||
            (url.size() > 1 && (url.at(0) == '/' || url.at(1) == ':'))) {
            QString localPath = url;
            if (localPath.startsWith(QStringLiteral("file:///")))
                localPath = QUrl(localPath).toLocalFile();
            QImageReader reader(localPath);
            reader.setScaledSize(QSize(targetW, targetH));
            QImage img = reader.read();
            if (!img.isNull()) {
                QMutexLocker lock(&m_mutex);
                m_cache.insert(url, new QImage(img));
            }
            resp->setImage(img);
            return;
        }

        QNetworkRequest req{QUrl(url)};
        req.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::PreferCache);
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *reply = m_nam->get(req);
        QObject::connect(reply, &QNetworkReply::finished, this,
                         [this, reply, resp, url, targetW, targetH]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                qWarning() << "[AvatarProvider] 下载失败" << url << reply->errorString();
                resp->setError(reply->errorString());
                return;
            }
            QByteArray data = reply->readAll();
            // 解码到目标尺寸 —— 在线程池里做，不阻塞 UI
            QtConcurrent::run([this, resp, url, targetW, targetH, data]() {
                QBuffer buf;
                buf.setData(data);
                buf.open(QIODevice::ReadOnly);
                QImageReader reader(&buf);
                // 解码时直接缩放到 2× 目标尺寸（适配高 DPI）
                reader.setScaledSize(QSize(targetW, targetH));
                QImage img = reader.read();
                if (img.isNull()) {
                    QMetaObject::invokeMethod(resp, [resp]() {
                        resp->setError(QStringLiteral("decode failed"));
                    }, Qt::QueuedConnection);
                    return;
                }
                {
                    QMutexLocker lock(&m_mutex);
                    m_cache.insert(url, new QImage(img));
                }
                QMetaObject::invokeMethod(resp, [resp, img]() {
                    resp->setImage(img);
                }, Qt::QueuedConnection);
            });
        });
    }, Qt::QueuedConnection);

    return resp;
}
