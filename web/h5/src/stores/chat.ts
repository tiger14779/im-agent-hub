import { defineStore } from 'pinia'
import type { Message } from '@/types'

export const useChatStore = defineStore('chat', {
  state: () => ({
    messages: [] as Message[],
    loading: false,
    hasMore: true
  }),

  actions: {
    addMessage(msg: Message) {
      // Avoid duplicate messages by clientMsgID
      const exists = this.messages.some((m) => m.clientMsgID === msg.clientMsgID)
      if (!exists) {
        this.messages.push(msg)
      }
    },

    updateMessageStatus(clientMsgID: string, status: number, serverMsgID?: string) {
      const msg = this.messages.find((m) => m.clientMsgID === clientMsgID)
      if (msg) {
        msg.status = status
        if (serverMsgID) msg.serverMsgID = serverMsgID
      }
    },

    /** Prepend older messages loaded from history */
    loadHistory(msgs: Message[]) {
      // Filter out duplicates then prepend
      const existing = new Set(this.messages.map((m) => m.clientMsgID))
      const newMsgs = msgs.filter((m) => !existing.has(m.clientMsgID))
      this.messages = [...newMsgs, ...this.messages]
    },

    clearMessages() {
      this.messages = []
      this.hasMore = true
    }
  }
})
