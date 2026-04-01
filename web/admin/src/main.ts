import { createApp } from 'vue'
import { createPinia } from 'pinia'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import * as ElementPlusIconsVue from '@element-plus/icons-vue'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import App from './App.vue'
import router from './router'

if (typeof window !== 'undefined' && window.performance) {
  const perf = window.performance as Performance & {
    clearMarks?: (markName?: string) => void
    clearMeasures?: (measureName?: string) => void
  }

  if (typeof perf.clearMarks !== 'function') {
    perf.clearMarks = () => {}
  }

  if (typeof perf.clearMeasures !== 'function') {
    perf.clearMeasures = () => {}
  }
}

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.use(ElementPlus, { locale: zhCn })

for (const [key, component] of Object.entries(ElementPlusIconsVue)) {
  app.component(key, component)
}

app.mount('#app')
