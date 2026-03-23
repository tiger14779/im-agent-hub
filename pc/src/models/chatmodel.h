#ifndef CHATMODEL_H
#define CHATMODEL_H

#include <QAbstractListModel>
#include <QJsonObject>
#include <QDateTime>
#include <QtQml/qqmlregistration.h>

struct ChatMessage {
    QString clientMsgID;
    QString sendID;
    QString recvID;
    int contentType = 101; // 101=text, 102=image, 103=voice, 105=file
    QString textContent;
    QString imageUrl;
    QString fileName;
    qint64 fileSize = 0;
    int voiceDuration = 0; // seconds
    qint64 sendTime = 0;
    int status = 2; // 1=sending, 2=sent, 3=failed
};

class ChatModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        ClientMsgIDRole = Qt::UserRole + 1,
        SendIDRole,
        RecvIDRole,
        ContentTypeRole,
        TextContentRole,
        ImageUrlRole,
        FileNameRole,
        FileSizeRole,
        VoiceDurationRole,
        SendTimeRole,
        StatusRole,
        IsSelfRole
    };

    explicit ChatModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_messages.size(); }

    Q_INVOKABLE void setSelfId(const QString &id) { m_selfId = id; }

    // Add a message to the list
    Q_INVOKABLE void appendMessage(const QJsonObject &msg);

    // Add a local temp message (optimistic send)
    Q_INVOKABLE QString addPendingMessage(const QString &recvId, int contentType,
                                           const QString &text, const QString &imageUrl = {},
                                           const QString &fileName = {}, qint64 fileSize = 0);

    // Update temp message status
    Q_INVOKABLE void updateStatus(const QString &clientMsgID, int status);

    // Clear all messages
    Q_INVOKABLE void clear();

signals:
    void countChanged();

private:
    ChatMessage fromJson(const QJsonObject &obj) const;

    QVector<ChatMessage> m_messages;
    QString m_selfId;
};

#endif // CHATMODEL_H
