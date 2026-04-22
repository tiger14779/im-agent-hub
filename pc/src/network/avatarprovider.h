#ifndef AVATARPROVIDER_H
#define AVATARPROVIDER_H

#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QImage>
#include <QCache>
#include <QMutex>
#include <QObject>
#include <QNetworkAccessManager>

class AvatarProvider;

// 单个头像加载响应，runOnUiThread → finished 信号通知 QML
class AvatarResponse : public QQuickImageResponse
{
    Q_OBJECT
public:
    QQuickTextureFactory *textureFactory() const override;
    void setImage(const QImage &img);
    void setError(const QString &err);

private:
    QImage m_image;
    QString m_error;
};

// 按 URL 索引的头像 LRU 内存缓存 + 异步下载/解码
// 在 QML 中通过 image://avatar/<完整URL> 使用
//
// 工作流程：
//   1. requestImageResponse(url, sourceSize) 被 QML Image 异步调用
//   2. 命中内存缓存 → 立即 finished()
//   3. 未命中 → 走 QNetworkAccessManager 下载（受 QML NAM 的磁盘缓存保护）
//   4. 解码到目标尺寸 → 入缓存 → finished()
//
// 同一 URL 在多处复用时共享同一份 QImage，滑动列表反复回收/重建 delegate
// 不会触发任何重新下载或重新解码。
class AvatarProvider : public QQuickAsyncImageProvider
{
    // QQuickAsyncImageProvider 已继承自 QObject，但未带 Q_OBJECT 宏
    // 这里不需要信号/槽，所以也不加 Q_OBJECT
public:
    explicit AvatarProvider();

    QQuickImageResponse *requestImageResponse(const QString &id,
                                              const QSize &requestedSize) override;

    // 设置缓存条目数（默认 500）
    void setCacheCapacity(int n);

private:
    mutable QMutex m_mutex;
    QCache<QString, QImage> m_cache;     // key = URL，value = 已解码的 QImage
    QNetworkAccessManager *m_nam;        // 复用同一个 NAM，享用其磁盘缓存

    friend class AvatarResponse;
};

#endif // AVATARPROVIDER_H
