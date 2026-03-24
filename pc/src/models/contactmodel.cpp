#include "contactmodel.h"

ContactModel::ContactModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ContactModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_contacts.size();
}

QVariant ContactModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_contacts.size())
        return {};

    const Contact &c = m_contacts.at(index.row());
    switch (role) {
    case UserIdRole:      return c.userId;
    case NicknameRole:    return c.nickname;
    case AvatarUrlRole:   return c.avatarUrl;
    case LastMessageRole: return c.lastMessage;
    case LastTimeRole:    return c.lastTime;
    case UnreadCountRole: return c.unreadCount;
    }
    return {};
}

QHash<int, QByteArray> ContactModel::roleNames() const
{
    return {
        { UserIdRole,      "userId" },
        { NicknameRole,    "nickname" },
        { AvatarUrlRole,   "avatarUrl" },
        { LastMessageRole, "lastMessage" },
        { LastTimeRole,    "lastTime" },
        { UnreadCountRole, "unreadCount" },
    };
}

void ContactModel::loadFromJson(const QJsonArray &arr)
{
    beginResetModel();
    m_contacts.clear();
    for (const auto &val : arr) {
        QJsonObject obj = val.toObject();
        Contact c;
        c.userId = obj["userId"].toString();
        c.nickname = obj["nickname"].toString();
        c.avatarUrl = obj["avatar"].toString();
        c.unreadCount = obj["unreadCount"].toInt(0);
        c.lastMessage = obj["lastMessage"].toString();
        c.lastTime = static_cast<qint64>(obj["lastTime"].toDouble(0));
        m_contacts.append(c);
    }
    endResetModel();
    emit countChanged();
    emit totalUnreadChanged();
}

void ContactModel::addOrUpdate(const QString &userId, const QString &nickname,
                                const QString &avatarUrl)
{
    int idx = findByUserId(userId);
    if (idx >= 0) {
        m_contacts[idx].nickname = nickname;
        if (!avatarUrl.isEmpty())
            m_contacts[idx].avatarUrl = avatarUrl;
        QModelIndex mi = index(idx);
        emit dataChanged(mi, mi, { NicknameRole, AvatarUrlRole });
    } else {
        beginInsertRows(QModelIndex(), m_contacts.size(), m_contacts.size());
        m_contacts.append({ userId, nickname, avatarUrl, {}, 0, 0 });
        endInsertRows();
        emit countChanged();
    }
}

void ContactModel::updateNickname(const QString &userId, const QString &nickname)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].nickname = nickname;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { NicknameRole });
}

void ContactModel::updateAvatar(const QString &userId, const QString &avatarUrl)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].avatarUrl = avatarUrl;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { AvatarUrlRole });
}

void ContactModel::updateLastMessage(const QString &userId, const QString &text, qint64 time)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].lastMessage = text;
    m_contacts[idx].lastTime = time;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { LastMessageRole, LastTimeRole });
}

void ContactModel::incrementUnread(const QString &userId)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].unreadCount++;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { UnreadCountRole });
    emit totalUnreadChanged();
}

void ContactModel::clearUnread(const QString &userId)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].unreadCount = 0;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { UnreadCountRole });
    emit totalUnreadChanged();
}

void ContactModel::clear()
{
    beginResetModel();
    m_contacts.clear();
    endResetModel();
    emit countChanged();
    emit totalUnreadChanged();
}

int ContactModel::totalUnread() const
{
    int sum = 0;
    for (const auto &c : m_contacts)
        sum += c.unreadCount;
    return sum;
}

QString ContactModel::getNickname(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return userId;
    return m_contacts[idx].nickname;
}

QString ContactModel::getAvatar(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return {};
    return m_contacts[idx].avatarUrl;
}

QJsonArray ContactModel::toJsonArray() const
{
    QJsonArray arr;
    for (const auto &c : m_contacts) {
        QJsonObject obj;
        obj["wxid"]   = c.userId;
        obj["wxNum"]  = QString();
        obj["nick"]   = c.nickname;
        obj["remark"] = QString();
        arr.append(obj);
    }
    return arr;
}

int ContactModel::findByUserId(const QString &userId) const
{
    for (int i = 0; i < m_contacts.size(); ++i) {
        if (m_contacts[i].userId == userId)
            return i;
    }
    return -1;
}
