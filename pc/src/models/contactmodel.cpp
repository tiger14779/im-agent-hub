#include "contactmodel.h"

ContactModel::ContactModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ContactModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_filteredIndices.size();
}

QVariant ContactModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_filteredIndices.size())
        return {};

    const Contact &c = m_contacts.at(m_filteredIndices.at(index.row()));
    switch (role) {
    case UserIdRole:      return c.userId;
    case NicknameRole:    return c.nickname;
    case AvatarUrlRole:   return c.avatarUrl;
    case LastMessageRole: return c.lastMessage;
    case LastTimeRole:    return c.lastTime;
    case UnreadCountRole: return c.unreadCount;
    case OnlineStatusRole: return c.onlineStatus;
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
        { OnlineStatusRole, "onlineStatus" },
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
    rebuildFilter();
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
        int fRow = filteredRow(idx);
        if (fRow >= 0) {
            QModelIndex mi = index(fRow);
            emit dataChanged(mi, mi, { NicknameRole, AvatarUrlRole });
        }
    } else {
        int realIdx = m_contacts.size();
        m_contacts.append({ userId, nickname, avatarUrl, {}, 0, 0 });
        // 检查新联系人是否匹配当前过滤条件
        bool matches = m_filterText.isEmpty()
            || nickname.contains(m_filterText, Qt::CaseInsensitive)
            || userId.contains(m_filterText, Qt::CaseInsensitive);
        if (matches) {
            int newFilteredRow = m_filteredIndices.size();
            beginInsertRows(QModelIndex(), newFilteredRow, newFilteredRow);
            m_filteredIndices.append(realIdx);
            endInsertRows();
        }
        emit countChanged();
    }
}

void ContactModel::updateNickname(const QString &userId, const QString &nickname)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].nickname = nickname;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { NicknameRole });
    }
}

void ContactModel::updateAvatar(const QString &userId, const QString &avatarUrl)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].avatarUrl = avatarUrl;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { AvatarUrlRole });
    }
}

void ContactModel::updateLastMessage(const QString &userId, const QString &text, qint64 time)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].lastMessage = text;
    m_contacts[idx].lastTime = time;
    int fRow = filteredRow(idx);
    if (fRow < 0) return;

    // 将该联系人移到列表顶部（不影响 activeUserId 选中状态）
    if (fRow > 0) {
        beginMoveRows(QModelIndex(), fRow, fRow, QModelIndex(), 0);
        m_filteredIndices.move(fRow, 0);
        endMoveRows();
    }
    QModelIndex mi = index(0);
    emit dataChanged(mi, mi, { LastMessageRole, LastTimeRole });
}

void ContactModel::incrementUnread(const QString &userId)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].unreadCount++;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { UnreadCountRole });
    }
    emit totalUnreadChanged();
}

void ContactModel::clearUnread(const QString &userId)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].unreadCount = 0;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { UnreadCountRole });
    }
    emit totalUnreadChanged();
}

void ContactModel::clear()
{
    beginResetModel();
    m_contacts.clear();
    m_filteredIndices.clear();
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

QString ContactModel::getOnlineStatus(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return QStringLiteral("offline");
    return m_contacts[idx].onlineStatus.isEmpty() ? QStringLiteral("offline") : m_contacts[idx].onlineStatus;
}

void ContactModel::setOnlineStatus(const QString &userId, const QString &status)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    m_contacts[idx].onlineStatus = status;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { OnlineStatusRole });
    }
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

void ContactModel::setFilterText(const QString &text)
{
    if (m_filterText == text)
        return;
    m_filterText = text;
    emit filterTextChanged();

    beginResetModel();
    rebuildFilter();
    endResetModel();
    emit countChanged();
}

void ContactModel::rebuildFilter()
{
    m_filteredIndices.clear();
    for (int i = 0; i < m_contacts.size(); ++i) {
        if (m_filterText.isEmpty()
            || m_contacts[i].nickname.contains(m_filterText, Qt::CaseInsensitive)
            || m_contacts[i].userId.contains(m_filterText, Qt::CaseInsensitive)) {
            m_filteredIndices.append(i);
        }
    }
}

int ContactModel::filteredRow(int realIdx) const
{
    return m_filteredIndices.indexOf(realIdx);
}
