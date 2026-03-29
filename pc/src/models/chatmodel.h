#ifndef CHATMODEL_H
#define CHATMODEL_H

#include <QAbstractListModel>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 聊天消息结构体
 *
 * 存储单条聊天消息的所有字段，支持文本/图片/语音/文件多种类型。
 */
struct ChatMessage {
    QString clientMsgID;               // 客户端生成的消息ID（UUID）
    QString serverMsgID;               // 服务器端消息ID
    QString sendID;                    // 发送者用户ID
    QString recvID;                    // 接收者用户ID
    int contentType = 101;             // 消息类型: 101=文本, 102=图片, 103=语音, 105=文件
    QString textContent;               // 文本内容（contentType=101 时使用）
    QString imageUrl;                  // 图片/文件/语音的服务器URL
    QString fileName;                  // 文件名（contentType=105 时使用）
    qint64 fileSize = 0;               // 文件大小（字节）
    int voiceDuration = 0;             // 语音时长（秒，contentType=103 时使用）
    qint64 sendTime = 0;               // 发送时间戳（毫秒）
    int status = 2;                    // 发送状态: 1=发送中, 2=已发送, 3=发送失败
};

/**
 * @brief 聊天消息列表模型 —— 为 QML ListView 提供消息数据
 *
 * 支持功能：添加消息、乐观发送（先显示再确认）、更新发送状态、清空消息。
 */
class ChatModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)  // 消息数量

public:
    // QML 可访问的角色枚举，对应 delegate 中的 model.xxx 属性
    enum Roles {
        ClientMsgIDRole = Qt::UserRole + 1,  // 客户端消息ID
        ServerMsgIDRole,                     // 服务器端消息ID
        SendIDRole,                          // 发送者ID
        RecvIDRole,                          // 接收者ID
        ContentTypeRole,                     // 消息类型
        TextContentRole,                     // 文本内容
        ImageUrlRole,                        // 图片/文件URL
        FileNameRole,                        // 文件名
        FileSizeRole,                        // 文件大小
        VoiceDurationRole,                   // 语音时长
        SendTimeRole,                        // 发送时间
        StatusRole,                          // 发送状态
        IsSelfRole                           // 是否为自己发送
    };

    explicit ChatModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_messages.size(); }

    Q_INVOKABLE void setSelfId(const QString &id) { m_selfId = id; }  // 设置当前用户ID，用于判断 isSelf

    // 添加一条服务器返回的消息
    Q_INVOKABLE void appendMessage(const QJsonObject &msg);

    // 批量插入历史消息到列表头部（加载更多旧消息）
    Q_INVOKABLE void prependMessages(const QJsonArray &msgs);

    // 添加本地临时消息（乐观发送：先显示“发送中”，服务器确认后更新状态）
    Q_INVOKABLE QString addPendingMessage(const QString &recvId, int contentType,
                                           const QString &text, const QString &imageUrl = {},
                                           const QString &fileName = {}, qint64 fileSize = 0);

    // 更新临时消息的发送状态（1=发送中, 2=已发送, 3=失败）
    Q_INVOKABLE void updateStatus(const QString &clientMsgID, int status, const QString &serverMsgID = {});

    // 生成唯一消息ID（桥接器发送到非当前会话时使用）
    Q_INVOKABLE QString generateMsgId();

    // 检查是否已存在指定 clientMsgID 的消息（用于去重）
    Q_INVOKABLE bool hasMessage(const QString &clientMsgID) const;

    // 清空所有消息（切换会话时调用）
    Q_INVOKABLE void clear();

    // 根据 serverMsgID 删除消息
    Q_INVOKABLE void removeMessageByServerMsgID(const QString &serverMsgID);

signals:
    void countChanged();

private:
    // 将服务器 JSON 转换为 ChatMessage 结构体（支持多种消息格式）
    ChatMessage fromJson(const QJsonObject &obj) const;

    QVector<ChatMessage> m_messages;  // 消息列表
    QString m_selfId;                 // 当前用户ID（用于判断 isSelf）
};

#endif // CHATMODEL_H
