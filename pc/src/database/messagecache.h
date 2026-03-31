#ifndef MESSAGECACHE_H
#define MESSAGECACHE_H

#include <QObject>
#include <QSqlDatabase>
#include <QJsonObject>
#include <QJsonArray>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 本地消息缓存 —— 使用 SQLite 存储聊天消息
 *
 * 切换聊天窗口时优先从本地数据库加载消息，再从服务器拉取增量数据，
 * 大幅提升切换会话的流畅度。
 * 注册为 QML 单例，在 QML 中可直接通过 MessageCache 访问。
 */
class MessageCache : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit MessageCache(QObject *parent = nullptr);
    ~MessageCache() override;

    /// 初始化数据库（以当前用户ID隔离数据库文件）
    Q_INVOKABLE void init(const QString &userId);

    /// 保存一条消息到本地数据库（去重：clientMsgID 存在则更新）
    Q_INVOKABLE void saveMessage(const QJsonObject &msg);

    /// 批量保存消息
    Q_INVOKABLE void saveMessages(const QJsonArray &msgs);

    /// 加载某个会话的最新 N 条消息（按 sendTime 降序，返回升序排列）
    Q_INVOKABLE QJsonArray loadMessages(const QString &peerUserId, int limit = 50);

    /// 加载某个会话中 sendTime < beforeTime 的消息（用于加载更多历史）
    Q_INVOKABLE QJsonArray loadMessagesBefore(const QString &peerUserId, qint64 beforeTime, int limit = 50);

    /// 获取某个会话最新一条消息的 sendTime（用于判断从哪里开始拉取服务器数据）
    Q_INVOKABLE qint64 getLatestSendTime(const QString &peerUserId);

    /// 仅更新消息状态（不覆盖 rawJson 中的消息内容）
    Q_INVOKABLE void updateMessageStatus(const QString &clientMsgID, int status, const QString &serverMsgID, qint64 sendTime);

    /// 删除一条消息
    Q_INVOKABLE void removeMessage(const QString &serverMsgID);

    /// 清空某个会话的所有缓存消息
    Q_INVOKABLE void clearChat(const QString &peerUserId);

private:
    void createTable();
    QString peerIdFromMsg(const QJsonObject &msg, const QString &selfId) const;

    QSqlDatabase m_db;
    QString m_userId; // 当前登录用户ID
};

#endif // MESSAGECACHE_H
