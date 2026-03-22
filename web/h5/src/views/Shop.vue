<template>
  <!-- Taobao-style product decoy page -->
  <div class="shop-page">
    <!-- Top navigation bar -->
    <header class="shop-nav">
      <span class="shop-nav-title">商品详情</span>
    </header>

    <!-- Product image carousel (gradient placeholders) -->
    <div class="product-gallery">
      <div class="product-img-main" :style="{ background: gallery[currentImg] }">
        <span class="product-badge">正品保证</span>
      </div>
      <div class="gallery-dots">
        <span
          v-for="(_, i) in gallery"
          :key="i"
          class="dot"
          :class="{ active: i === currentImg }"
          @click="currentImg = i"
        />
      </div>
    </div>

    <!-- Price & title -->
    <div class="product-info">
      <div class="product-price">
        <span class="price-currency">¥</span>
        <span class="price-main">298</span>
        <span class="price-original">¥598</span>
        <span class="price-tag">限时折扣</span>
      </div>
      <h1 class="product-title">高品质商务休闲男士皮鞋 头层牛皮软底耐磨防滑</h1>
      <div class="product-meta">
        <span>月销 3,241</span>
        <span>好评率 98%</span>
        <span>48小时发货</span>
      </div>
    </div>

    <!-- Divider -->
    <div class="section-divider" />

    <!-- SKU selector -->
    <div class="product-sku">
      <div class="sku-row">
        <span class="sku-label">颜色</span>
        <div class="sku-options">
          <span
            v-for="c in colors"
            :key="c"
            class="sku-tag"
            :class="{ selected: selectedColor === c }"
            @click="selectedColor = c"
          >{{ c }}</span>
        </div>
      </div>
      <div class="sku-row">
        <span class="sku-label">尺码</span>
        <div class="sku-options">
          <span
            v-for="s in sizes"
            :key="s"
            class="sku-tag"
            :class="{ selected: selectedSize === s }"
            @click="selectedSize = s"
          >{{ s }}</span>
        </div>
      </div>
    </div>

    <div class="section-divider" />

    <!-- Product description — contains the hidden customer-service entrance -->
    <div class="product-desc">
      <h2 class="desc-title">商品描述</h2>
      <p>采用头层牛皮精心制作，皮面细腻光滑，具有良好的透气性和耐磨性。</p>
      <p>内里采用高密度海绵填充，脚感舒适，久穿不累。</p>
      <p>橡胶大底防滑耐磨，适合各种场合穿着，商务休闲两相宜。</p>
      <p>如有任何问题，欢迎随时
        <!-- Hidden entrance: clicking "联系客服" reveals the ID input -->
        <span class="contact-link" @click="showContactInput = true">联系客服</span>
        ，我们将竭诚为您服务。
      </p>

      <!-- Customer-service ID input (revealed on click) -->
      <transition name="slide-down">
        <div v-if="showContactInput" class="contact-input-box">
          <input
            v-model="inputId"
            type="text"
            placeholder="请输入客服 ID"
            class="contact-id-input"
            @keyup.enter="goToChat"
          />
          <button class="contact-go-btn" @click="goToChat">进入咨询</button>
          <button class="contact-cancel-btn" @click="showContactInput = false">取消</button>
        </div>
      </transition>
    </div>

    <div class="section-divider" />

    <!-- Evaluation summary -->
    <div class="product-reviews">
      <h2 class="desc-title">买家评价 (1,028)</h2>
      <div v-for="r in reviews" :key="r.name" class="review-item">
        <div class="review-header">
          <span class="review-name">{{ r.name }}</span>
          <span class="review-stars">★★★★★</span>
        </div>
        <p class="review-text">{{ r.text }}</p>
      </div>
    </div>

    <transition name="fade">
      <div v-if="toast" class="shop-toast">{{ toast }}</div>
    </transition>
    <div class="shop-action-bar">
      <!-- Very subtle customer-service button -->
      <button class="cs-btn" @click="showContactInput = true">客服</button>
      <button class="cart-btn" @click="onCart">加入购物车</button>
      <button class="buy-btn" @click="onBuy">立即购买</button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'

const router = useRouter()
const route = useRoute()

const currentImg = ref(0)
const gallery = [
  'linear-gradient(135deg, #8B6914 0%, #C8A951 100%)',
  'linear-gradient(135deg, #2C2C2C 0%, #555555 100%)',
  'linear-gradient(135deg, #5C3317 0%, #8B5E3C 100%)'
]

const colors = ['棕色', '黑色', '咖啡色']
const sizes = ['38', '39', '40', '41', '42', '43', '44']
const selectedColor = ref('棕色')
const selectedSize = ref('42')

const reviews = [
  { name: '买家***88', text: '质量很好，皮质柔软，穿着舒适，和描述一致，很满意！' },
  { name: '用户***23', text: '发货速度快，包装精美，鞋子做工精细，穿上很有档次。' },
  { name: '顾客***55', text: '性价比超高，已经是第三次购买了，非常推荐！' }
]

const showContactInput = ref(false)
const inputId = ref('')
const toast = ref('')

let toastTimer: ReturnType<typeof setTimeout> | null = null
function showToast(msg: string) {
  toast.value = msg
  if (toastTimer) clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = '' }, 2000)
}

function goToChat() {
  const id = inputId.value.trim()
  if (!id) return
  router.push({ path: '/chat', query: { id } })
}

function onCart() {
  showToast('已加入购物车')
}

function onBuy() {
  showToast('请先登录后再购买')
}

// Auto-navigate if the URL already contains ?id=
onMounted(() => {
  const id = route.query.id as string | undefined
  if (id) {
    router.replace({ path: '/chat', query: { id } })
  }
})
</script>

<style scoped>
.shop-page {
  width: 100%;
  height: 100%;
  overflow-y: auto;
  background: #f4f4f4;
  padding-bottom: 70px;
}

/* Nav */
.shop-nav {
  position: sticky;
  top: 0;
  z-index: 10;
  height: 44px;
  background: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  border-bottom: 1px solid #e5e5e5;
}

.shop-nav-title {
  font-size: 16px;
  font-weight: 500;
}

/* Gallery */
.product-gallery {
  position: relative;
  background: #fff;
}

.product-img-main {
  width: 100%;
  height: 375px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.product-badge {
  background: rgba(0, 0, 0, 0.4);
  color: #fff;
  font-size: 12px;
  padding: 3px 8px;
  border-radius: 10px;
  position: absolute;
  top: 12px;
  right: 12px;
}

.gallery-dots {
  display: flex;
  justify-content: center;
  gap: 6px;
  padding: 8px 0;
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #ccc;
}

.dot.active {
  background: #ff4400;
  width: 12px;
  border-radius: 3px;
}

/* Product info */
.product-info {
  background: #fff;
  padding: 12px;
}

.product-price {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin-bottom: 8px;
}

.price-currency {
  color: #ff4400;
  font-size: 14px;
}

.price-main {
  color: #ff4400;
  font-size: 28px;
  font-weight: 700;
}

.price-original {
  color: #999;
  font-size: 13px;
  text-decoration: line-through;
}

.price-tag {
  background: #ff4400;
  color: #fff;
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 3px;
}

.product-title {
  font-size: 15px;
  font-weight: 500;
  line-height: 1.5;
  color: #333;
  margin-bottom: 8px;
}

.product-meta {
  display: flex;
  gap: 12px;
  font-size: 12px;
  color: #999;
}

/* Divider */
.section-divider {
  height: 8px;
  background: #f4f4f4;
}

/* SKU */
.product-sku {
  background: #fff;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.sku-row {
  display: flex;
  align-items: center;
  gap: 10px;
}

.sku-label {
  font-size: 13px;
  color: #666;
  width: 36px;
  flex-shrink: 0;
}

.sku-options {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.sku-tag {
  padding: 4px 12px;
  border: 1px solid #e5e5e5;
  border-radius: 4px;
  font-size: 13px;
  color: #333;
}

.sku-tag.selected {
  border-color: #ff4400;
  color: #ff4400;
  background: #fff5f0;
}

/* Description */
.product-desc {
  background: #fff;
  padding: 12px;
}

.desc-title {
  font-size: 15px;
  font-weight: 500;
  margin-bottom: 10px;
  color: #333;
}

.product-desc p {
  font-size: 13px;
  color: #666;
  line-height: 1.8;
  margin-bottom: 4px;
}

/* Hidden customer-service link */
.contact-link {
  color: #1989fa;
  cursor: pointer;
}

.contact-input-box {
  margin-top: 10px;
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}

.contact-id-input {
  flex: 1;
  min-width: 0;
  height: 34px;
  border: 1px solid #e5e5e5;
  border-radius: 4px;
  padding: 0 10px;
  font-size: 13px;
  color: #333;
  background: #f9f9f9;
}

.contact-go-btn {
  height: 34px;
  padding: 0 14px;
  background: #07c160;
  color: #fff;
  border-radius: 4px;
  font-size: 13px;
}

.contact-cancel-btn {
  height: 34px;
  padding: 0 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 13px;
  color: #666;
}

/* Reviews */
.product-reviews {
  background: #fff;
  padding: 12px;
}

.review-item {
  padding: 10px 0;
  border-bottom: 1px solid #f4f4f4;
}

.review-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 4px;
}

.review-name {
  font-size: 12px;
  color: #999;
}

.review-stars {
  color: #ffa500;
  font-size: 12px;
}

.review-text {
  font-size: 13px;
  color: #555;
  line-height: 1.6;
}

/* Toast */
.shop-toast {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background: rgba(0, 0, 0, 0.7);
  color: #fff;
  font-size: 14px;
  padding: 10px 20px;
  border-radius: 6px;
  z-index: 999;
  pointer-events: none;
}

/* Bottom action bar */
.shop-action-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  height: 56px;
  background: #fff;
  border-top: 1px solid #e5e5e5;
  display: flex;
  align-items: center;
  padding: 0 10px;
  gap: 8px;
}

.cs-btn {
  width: 44px;
  height: 40px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  color: #666;
  flex-shrink: 0;
  gap: 2px;
}

.cart-btn {
  flex: 1;
  height: 40px;
  border-radius: 20px;
  background: #ff9900;
  color: #fff;
  font-size: 14px;
  font-weight: 500;
}

.buy-btn {
  flex: 1;
  height: 40px;
  border-radius: 20px;
  background: #ff4400;
  color: #fff;
  font-size: 14px;
  font-weight: 500;
}

/* Slide-down transition for contact input */
.slide-down-enter-active,
.slide-down-leave-active {
  transition: all 0.2s ease;
}

.slide-down-enter-from,
.slide-down-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}
</style>
