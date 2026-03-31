#ifndef CONTACTMODEL_H
#define CONTACTMODEL_H

#include <QAbstractListModel>
#include <QJsonObject>
#include <QJsonArray>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 联系人结构体
 *
 * 存储单个联系人的信息，包括最后一条消息和未读数量。
 */
struct Contact {
    QString userId;       // 用户ID
    QString nickname;     // 昵称
    QString avatarUrl;    // 头像URL
    QString lastMessage;  // 最后一条消息预览
    qint64 lastTime = 0;  // 最后消息时间戳
    int unreadCount = 0;  // 未读消息数
    QString onlineStatus; // 在线状态: "online", "background", "offline"
};

/**
 * @brief 联系人列表模型 —— 为 QML ListView 提供联系人数据
 *
 * 支持功能：从服务器加载、增删改查、未读计数、导出为 JSON 数组。
 */
class ContactModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)         // 联系人数量
    Q_PROPERTY(int totalUnread READ totalUnread NOTIFY totalUnreadChanged)  // 总未读数
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)  // 搜索过滤文本

public:
    // QML 可访问的角色枚举
    enum Roles {
        UserIdRole = Qt::UserRole + 1,   // 用户ID
        NicknameRole,                    // 昵称
        AvatarUrlRole,                   // 头像URL
        LastMessageRole,                 // 最后一条消息
        LastTimeRole,                    // 最后消息时间
        UnreadCountRole,                 // 未读数
        OnlineStatusRole                 // 在线状态
    };

    explicit ContactModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_filteredIndices.size(); }
    int totalUnread() const;

    QString filterText() const { return m_filterText; }
    void setFilterText(const QString &text);

    // 从服务器返回的 JSON 数组加载联系人列表（会清空现有数据）
    Q_INVOKABLE void loadFromJson(const QJsonArray &arr);

    // 添加或更新联系人（已存在则更新昵称和头像）
    Q_INVOKABLE void addOrUpdate(const QString &userId, const QString &nickname,
                                  const QString &avatarUrl = {});
    // 更新联系人昵称
    Q_INVOKABLE void updateNickname(const QString &userId, const QString &nickname);
    // 更新联系人头像
    Q_INVOKABLE void updateAvatar(const QString &userId, const QString &avatarUrl);
    // 更新最后一条消息预览和时间
    Q_INVOKABLE void updateLastMessage(const QString &userId, const QString &text, qint64 time);
    // 增加未读计数
    Q_INVOKABLE void incrementUnread(const QString &userId);
    // 清除未读计数（切换到该会话时调用）
    Q_INVOKABLE void clearUnread(const QString &userId);
    // 清空所有联系人
    Q_INVOKABLE void clear();

    // 获取指定用户的昵称，找不到则返回 userId
    Q_INVOKABLE QString getNickname(const QString &userId) const;
    // 获取指定用户的头像URL
    Q_INVOKABLE QString getAvatar(const QString &userId) const;
    // 获取指定用户的在线状态
    Q_INVOKABLE QString getOnlineStatus(const QString &userId) const;
    // 设置指定用户的在线状态
    Q_INVOKABLE void setOnlineStatus(const QString &userId, const QString &status);
    // 导出联系人列表为 JSON 数组（用于推送给财务软件）
    Q_INVOKABLE QJsonArray toJsonArray() const;

signals:
    void countChanged();
    void totalUnreadChanged();
    void filterTextChanged();

private:
    // 根据 userId 查找联系人在列表中的索引，未找到返回 -1
    int findByUserId(const QString &userId) const;
    // 重建过滤索引列表
    void rebuildFilter();
    // 将真实索引映射为过滤后的行号，不可见返回 -1
    int filteredRow(int realIdx) const;

    QVector<Contact> m_contacts;         // 联系人列表（完整）
    QVector<int> m_filteredIndices;      // 过滤后的索引映射
    QString m_filterText;                // 当前搜索关键词
};

#endif // CONTACTMODEL_H
