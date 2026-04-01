import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './styles/reset.css'
import './styles/variables.css'
import './styles/chat.css'

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
app.mount('#app')
