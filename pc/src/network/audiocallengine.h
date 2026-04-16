#ifndef AUDIOCALLENGINE_H
#define AUDIOCALLENGINE_H

#include <QObject>
#include <QIODevice>
#include <QWebSocket>
#include <QAudioSource>
#include <QAudioSink>
#include <QAudioFormat>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QStringList>
#include <QByteArray>
#include <QMutex>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 线程安全的环形缓冲区，供 QAudioSink pull 模式使用。
 *
 * QAudioSink 以 pull 模式从此 device 读取数据：
 *   - 有数据时正常返回；
 *   - 缓冲不足时填充静音（0），避免爆音/噪音。
 */
class AudioRingBuffer : public QIODevice
{
    Q_OBJECT
public:
    explicit AudioRingBuffer(QObject *parent = nullptr);
    void push(const QByteArray &data);  // 从网络线程写入

    // 必须声明为顺序设备，否则 Qt 内部将尝试 seek 导致 readData 不被调用
    bool isSequential() const override { return true; }
    // 返回缓冲区字节数；空时返回一个大数保证 sink 持续拉取静音
    qint64 bytesAvailable() const override;

protected:
    qint64 readData(char *data, qint64 maxSize) override;
    qint64 writeData(const char *data, qint64 maxSize) override;

private:
    mutable QMutex m_mutex;
    QByteArray     m_buf;
    static constexpr int kMaxBufBytes = 192000; // 约 0.5s @ 48kHz Float32 双声道
};

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

    QStringList inputDevices()  const;
    QStringList outputDevices() const;

    Q_INVOKABLE void start(const QString &wsBase, const QString &serverBaseUrl,
                           const QString &roomId, const QString &token,
                           const QString &inputId  = {},
                           const QString &outputId = {});
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void playRingtone();
    Q_INVOKABLE void stopRingtone();

signals:
    void activeChanged();
    void mutedChanged();
    void devicesChanged();
    void errorOccurred(const QString &msg);
    void peerSpeaking(bool speaking);

private slots:
    void onWsConnected();
    void onWsDisconnected();
    void onWsError(QAbstractSocket::SocketError err);
    void onCaptureReady();
    void onAudioFrame(const QByteArray &data);
    void onRingtoneTick();

private:
    static QAudioFormat audioFormat();
    static qint16 rms(const QByteArray &pcm16);
    static QString buildUrl(const QString &wsBase, const QString &serverBaseUrl,
                            const QString &roomId, const QString &token);
    static QByteArray convertToWire(const QByteArray &raw, const QAudioFormat &src);
    static QByteArray convertFromWire(const QByteArray &wire, const QAudioFormat &dst);

    QWebSocket        m_ws;
    QAudioSource     *m_source          = nullptr;
    QAudioSink       *m_sink            = nullptr;
    QIODevice        *m_captureDevice   = nullptr;
    AudioRingBuffer  *m_ringBuffer      = nullptr;
    bool              m_active          = false;
    bool              m_muted           = false;
    QAudioFormat      m_captureFormat;
    QAudioFormat      m_playbackFormat;

    // 铃声合成
    QAudioSink       *m_ringtoneSink    = nullptr;
    AudioRingBuffer  *m_ringtoneBuffer  = nullptr;
    QTimer           *m_ringtoneTimer   = nullptr;
    int               m_ringSamplePos   = 0;
};

#endif // AUDIOCALLENGINE_H

