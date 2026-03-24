#ifndef CONTACTMODEL_H
#define CONTACTMODEL_H

#include <QAbstractListModel>
#include <QJsonObject>
#include <QJsonArray>
#include <QtQml/qqmlregistration.h>

struct Contact {
    QString userId;
    QString nickname;
    QString avatarUrl;
    QString lastMessage;
    qint64 lastTime = 0;
    int unreadCount = 0;
};

class ContactModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalUnread READ totalUnread NOTIFY totalUnreadChanged)

public:
    enum Roles {
        UserIdRole = Qt::UserRole + 1,
        NicknameRole,
        AvatarUrlRole,
        LastMessageRole,
        LastTimeRole,
        UnreadCountRole
    };

    explicit ContactModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_contacts.size(); }
    int totalUnread() const;

    // Load contacts from server JSON array
    Q_INVOKABLE void loadFromJson(const QJsonArray &arr);

    Q_INVOKABLE void addOrUpdate(const QString &userId, const QString &nickname,
                                  const QString &avatarUrl = {});
    Q_INVOKABLE void updateNickname(const QString &userId, const QString &nickname);
    Q_INVOKABLE void updateAvatar(const QString &userId, const QString &avatarUrl);
    Q_INVOKABLE void updateLastMessage(const QString &userId, const QString &text, qint64 time);
    Q_INVOKABLE void incrementUnread(const QString &userId);
    Q_INVOKABLE void clearUnread(const QString &userId);
    Q_INVOKABLE void clear();

    Q_INVOKABLE QString getNickname(const QString &userId) const;
    Q_INVOKABLE QString getAvatar(const QString &userId) const;
    Q_INVOKABLE QJsonArray toJsonArray() const;

signals:
    void countChanged();
    void totalUnreadChanged();

private:
    int findByUserId(const QString &userId) const;
    QVector<Contact> m_contacts;
};

#endif // CONTACTMODEL_H
