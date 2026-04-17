#include "contactmodel.h"
#include <algorithm>

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
    case IsGroupRole:     return c.isGroup;
    case MemberCountRole: return c.memberCount;
    case GroupNicknameRole: return c.groupNickname;
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
        { IsGroupRole,     "isGroup" },
        { MemberCountRole, "memberCount" },
        { GroupNicknameRole, "groupNickname" },
    };
}

void ContactModel::loadFromJson(const QJsonArray &arr, bool isGroup)
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
        c.groupNickname = obj["groupNickname"].toString();
        c.isGroup = isGroup;
        if (isGroup) {
            c.userId = obj["id"].toString();
            c.nickname = obj["name"].toString();
            c.memberCount = obj["memberCount"].toInt(0);
        }
        m_contacts.append(c);
    }
    // 群组始终置顶，群组内部 / 非群组内部再按最后消息时间降序
    std::stable_sort(m_contacts.begin(), m_contacts.end(), [](const Contact &a, const Contact &b) {
        if (a.isGroup != b.isGroup) return a.isGroup > b.isGroup;
        return a.lastTime > b.lastTime;
    });
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

void ContactModel::addOrUpdateAsGroup(const QString &groupId, const QString &name, int memberCount, const QString &avatarUrl)
{
    int idx = findByUserId(groupId);
    if (idx >= 0) {
        m_contacts[idx].nickname    = name;
        m_contacts[idx].isGroup     = true;
        m_contacts[idx].memberCount = memberCount;
        if (!avatarUrl.isEmpty())
            m_contacts[idx].avatarUrl = avatarUrl;
        int fRow = filteredRow(idx);
        if (fRow >= 0) {
            QModelIndex mi = index(fRow);
            emit dataChanged(mi, mi, { NicknameRole, IsGroupRole, MemberCountRole, AvatarUrlRole });
        }
    } else {
        int realIdx = m_contacts.size();
        Contact c;
        c.userId      = groupId;
        c.nickname    = name;
        c.isGroup     = true;
        c.memberCount = memberCount;
        c.avatarUrl   = avatarUrl;
        m_contacts.append(c);
        bool matches = m_filterText.isEmpty()
            || name.contains(m_filterText, Qt::CaseInsensitive)
            || groupId.contains(m_filterText, Qt::CaseInsensitive);
        if (matches) {
            // 群组始终置顶：插入到已有群组之后、第一个非群组之前
            int insertRow = 0;
            for (int i = 0; i < m_filteredIndices.size(); ++i) {
                if (m_contacts[m_filteredIndices[i]].isGroup)
                    insertRow = i + 1;
                else
                    break;
            }
            beginInsertRows(QModelIndex(), insertRow, insertRow);
            m_filteredIndices.insert(insertRow, realIdx);
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

    // 群组始终置顶：移动目标位置 = 0（群）或群组区块结束后的第一行（非群）
    bool isGrp = m_contacts[idx].isGroup;
    int targetRow = 0;
    if (!isGrp) {
        // 跳过所有群组行
        for (int i = 0; i < m_filteredIndices.size(); ++i) {
            if (m_contacts[m_filteredIndices[i]].isGroup)
                targetRow = i + 1;
            else
                break;
        }
    }
    if (fRow > targetRow) {
        beginMoveRows(QModelIndex(), fRow, fRow, QModelIndex(), targetRow);
        m_filteredIndices.move(fRow, targetRow);
        endMoveRows();
    }
    QModelIndex mi = index(targetRow);
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

QString ContactModel::getGroupNickname(const QString &userId) const
{
    int idx = findByUserId(userId);
    if (idx < 0) return {};
    return m_contacts[idx].groupNickname;
}

void ContactModel::updateGroupNickname(const QString &userId, const QString &groupNickname)
{
    int idx = findByUserId(userId);
    if (idx < 0) return;
    if (m_contacts[idx].groupNickname == groupNickname) return;
    m_contacts[idx].groupNickname = groupNickname;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { GroupNicknameRole });
    }
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
    if (m_contacts[idx].onlineStatus == status) return;
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

void ContactModel::updateMemberCount(const QString &groupId, int count)
{
    int idx = findByUserId(groupId);
    if (idx < 0) return;
    m_contacts[idx].memberCount = count;
    int fRow = filteredRow(idx);
    if (fRow >= 0) {
        QModelIndex mi = index(fRow);
        emit dataChanged(mi, mi, { MemberCountRole });
    }
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
