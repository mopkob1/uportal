import { createApp } from 'vue'
import naive from 'naive-ui'
import store from './store'
import App from './App.vue'

createApp(App).use(store).use(naive).mount('#app')


