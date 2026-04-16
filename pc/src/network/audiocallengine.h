#ifndef AUDIOCALLENGINE_H
#define AUDIOCALLENGINE_H

#include <QObject>
#include <QWebSocket>
#include <QAudioSource>
#include <QAudioSink>
#include <QAudioFormat>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 纯 WebSocket PCM 音频通话引擎
 *
 * 使用 QAudioSource（麦克风采集）和 QAudioSink（扬声器播放），
 * 通过 WebSocket 将 PCM16 帧双向中继。
 *
 * 注册为 QML 单例，在 QML 中可直接通过 AudioCallEngine 访问。
 *
 * 音频参数：8000 Hz、PCM Int16、单声道、20ms 帧（320 字节/帧）。
 */
class AudioCallEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(bool muted READ isMuted NOTIFY mutedChanged)
    Q_PROPERTY(QStringList inputDevices  READ inputDevices  NOTIFY devicesChanged)
    Q_PROPERTY(QStringList outputDevices READ outputDevices NOTIFY devicesChanged)

public:
    explicit AudioCallEngine(QObject *parent = nullptr);
    ~AudioCallEngine() override;

    bool isActive() const { return m_active; }
    bool isMuted()  const { return m_muted;  }

    /** 返回输入设备描述列表（索引对应 inputDeviceIds() 中的设备 ID） */
    QStringList inputDevices()  const;
    /** 返回输出设备描述列表 */
    QStringList outputDevices() const;

    /**
     * @brief 启动通话
     * @param wsBase   中继服务器基础地址（空 = 使用主 WS 服务器的 /api/call/audio，
     *                 否则为完整的 wss:// 地址）
     * @param serverBaseUrl  主 WS 服务器地址（wsBase 为空时用于构造完整 URL）
     * @param roomId   房间 ID
     * @param token    HMAC 鉴权 Token
     * @param inputId  输入设备 ID（空 = 默认设备）
     * @param outputId 输出设备 ID（空 = 默认设备）
     */
    Q_INVOKABLE void start(const QString &wsBase, const QString &serverBaseUrl,
                           const QString &roomId, const QString &token,
                           const QString &inputId  = {},
                           const QString &outputId = {});
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setMuted(bool muted);

signals:
    void activeChanged();
    void mutedChanged();
    void devicesChanged();
    void errorOccurred(const QString &msg);
    /** 对端是否正在发言（基于简单 RMS 阈值） */
    void peerSpeaking(bool speaking);

private slots:
    void onWsConnected();
    void onWsDisconnected();
    void onWsError(QAbstractSocket::SocketError err);
    void onCaptureReady();
    void onAudioFrame(const QByteArray &data);

private:
    /** 返回统一的 8kHz/Int16/单声道 格式 */
    static QAudioFormat audioFormat();
    /** 计算 PCM16 帧的 RMS 值（用于 VAD） */
    static qint16 rms(const QByteArray &pcm16);
    /** 根据 wsBase 和 serverBaseUrl 构造完整的 wss:// URL */
    static QString buildUrl(const QString &wsBase, const QString &serverBaseUrl,
                            const QString &roomId, const QString &token);

    QWebSocket    m_ws;
    QAudioSource *m_source          = nullptr;
    QAudioSink   *m_sink            = nullptr;
    QIODevice    *m_captureDevice   = nullptr;
    QIODevice    *m_playbackDevice  = nullptr;
    bool          m_active          = false;
    bool          m_muted           = false;
};

#endif // AUDIOCALLENGINE_H
