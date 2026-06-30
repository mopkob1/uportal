<template>
  <n-grid :cols="2" :x-gap="12">
    <n-form-item :label="texts.fields.type">
      <n-select :value="type" :options="typeOptions" @update:value="emit('update:type', $event)" />
    </n-form-item>

    <n-form-item :label="texts.fields.publicationId">
      <n-input
          :value="publicationId"
          :placeholder="texts.placeholders.newPublication"
          @update:value="emit('update:publicationId', $event)"
      />
    </n-form-item>
  </n-grid>
</template>

<script setup>
defineProps({
  type: {
    type: String,
    required: true
  },
  publicationId: {
    type: String,
    default: ''
  },
  texts: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['update:type', 'update:publicationId'])

const typeOptions = [
  { label: 'Redirect', value: 'redirect' },
  { label: 'Page', value: 'page' },
  { label: 'Download', value: 'download' },
  { label: 'Pixel', value: 'pixel' }
]
</script>