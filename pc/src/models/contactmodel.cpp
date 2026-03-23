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
    case RemarkRole:      return c.remark;
    case DisplayNameRole: return c.displayName();
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
        { RemarkRole,      "remark" },
        { DisplayNameRole, "displayName" },
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
        c.remark = obj["remark"].toString();
        c.avatarUrl = obj["avatar"].toString();
        m_contacts.append(c);
    }
    endResetModel();
    emit countChanged();
}

void ContactModel::addOrUpdate(const QString &userId, const QString &nickname,
                                const QString &remark, const QString &avatarUrl)
{
    int idx = findByUserId(userId);
    if (idx >= 0) {
        m_contacts[idx].nickname = nickname;
        if (!remark.isNull())
            m_contacts[idx].remark = remark;
        if (!avatarUrl.isEmpty())
            m_contacts[idx].avatarUrl = avatarUrl;
        QModelIndex mi = index(idx);
        emit dataChanged(mi, mi, { NicknameRole, RemarkRole, DisplayNameRole, AvatarUrlRole });
    } else {
        beginInsertRows(QModelIndex(), m_contacts.size(), m_contacts.size());
        m_contacts.append({ userId, nickname, remark, avatarUrl, {}, 0, 0 });
        endInsertRows();
        emit countChanged();
    }
}

void ContactModel::updateRemark(const QString &userId, const QString &remark)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].remark = remark;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { RemarkRole, DisplayNameRole });
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
}

void ContactModel::clearUnread(const QString &userId)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].unreadCount = 0;
    QModelIndex mi = index(idx);
    emit dataChanged(mi, mi, { UnreadCountRole });
}

void ContactModel::clear()
{
    beginResetModel();
    m_contacts.clear();
    endResetModel();
    emit countChanged();
}

QString ContactModel::getDisplayName(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return userId;
    return m_contacts[idx].displayName();
}

QString ContactModel::getAvatar(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return {};
    return m_contacts[idx].avatarUrl;
}

int ContactModel::findByUserId(const QString &userId) const
{
    for (int i = 0; i < m_contacts.size(); ++i) {
        if (m_contacts[i].userId == userId)
            return i;
    }
    return -1;
}
