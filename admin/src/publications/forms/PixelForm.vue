<template>
  <n-alert type="info" :bordered="false">
    {{ texts.pixelForm.note }}
  </n-alert>
</template>

<script setup>
const props = defineProps({
  draft: {
    type: Object,
    required: true
  },
  texts: {
    type: Object,
    required: true
  }
})

const draft = props.draft
const texts = props.texts
</script>
