<script setup lang="ts">
import { ref, computed } from "vue"
import { useLiveVue, type Form, useLiveForm } from "live_vue"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"

type FilterType = "all" | "active" | "completed"

const props = defineProps<{
  todos: Array<{ id: number; text: string; completed: boolean }>
  form: Form<{ text: string }>
}>()

const live = useLiveVue()

const { field, submit, isValid } = useLiveForm<{ text: string }>(() => props.form, {
  submitEvent: "add_todo",
  changeEvent: "validate_todo",
  debounceInMiliseconds: 50,
})

const textField = field("text")

const filter = ref<FilterType>("all")

const filterByType = (type: FilterType) => {
  switch (type) {
    case "active":
      return props.todos.filter((todo) => !todo.completed)
    case "completed":
      return props.todos.filter((todo) => todo.completed)
    default:
      return props.todos
  }
}

const filteredTodos = computed(() => filterByType(filter.value))
const completedCount = computed(() => filterByType("completed").length)
</script>

<template>
  <div class="max-w-2xl mx-auto space-y-8">
    <!-- Header -->
    <div class="text-center space-y-2">
      <h1 class="text-4xl font-bold tracking-tight">🎉 Welcome to LiveVue!</h1>
      <p class="text-muted-foreground">Vue.js components seamlessly integrated with Phoenix LiveView</p>
    </div>

    <!-- Todo Card -->
    <Card>
      <CardHeader>
        <CardTitle>Todo demo</CardTitle>
        <CardDescription>
          Server-validated form, reactive props, client-only filtering — all in one component.
        </CardDescription>
      </CardHeader>
      <CardContent class="space-y-6">
        <!-- Add Todo Form -->
        <form @submit.prevent="submit" class="space-y-1">
          <div class="flex gap-2">
            <Input
              v-bind="textField.inputAttrs.value"
              type="text"
              placeholder="What needs to be done?"
              class="flex-1"
            />
            <Button type="submit" :disabled="!isValid">Add</Button>
          </div>
          <p
            v-if="(textField.isTouched.value || textField.isDirty.value) && textField.errorMessage.value"
            class="text-destructive text-xs"
          >
            {{ textField.errorMessage }}
          </p>
        </form>

        <!-- Filter Buttons -->
        <div class="flex gap-2">
          <Button
            v-for="filterType in ['all', 'active', 'completed'] as FilterType[]"
            :key="filterType"
            :variant="filter === filterType ? 'default' : 'outline'"
            size="sm"
            @click="filter = filterType"
          >
            {{ filterType.charAt(0).toUpperCase() + filterType.slice(1) }}
            ({{ filterByType(filterType).length }})
          </Button>
        </div>

        <!-- Todo List -->
        <div v-if="filteredTodos.length > 0" class="space-y-2">
          <div
            v-for="todo in filteredTodos"
            :key="todo.id"
            class="flex items-center gap-3 rounded-md border p-3"
          >
            <input
              type="checkbox"
              :checked="todo.completed"
              @change="live.pushEvent('toggle_todo', { id: todo.id })"
              class="size-4 rounded border-input cursor-pointer"
            />
            <span :class="['flex-1 text-sm', todo.completed && 'line-through text-muted-foreground']">
              {{ todo.text }}
            </span>
            <Button
              variant="ghost"
              size="sm"
              class="text-destructive hover:bg-destructive/10 hover:text-destructive"
              @click="live.pushEvent('delete_todo', { id: todo.id })"
            >
              Delete
            </Button>
          </div>
        </div>

        <p v-else class="text-sm text-muted-foreground py-8 text-center">
          {{ filter === "all" ? "No todos yet — add one above." : `No ${filter} todos.` }}
        </p>

        <!-- Actions -->
        <div
          v-if="props.todos.some((todo) => todo.completed)"
          class="flex justify-between items-center pt-2 border-t"
        >
          <span class="text-sm text-muted-foreground">{{ completedCount }} completed</span>
          <Button variant="outline" size="sm" @click="live.pushEvent('clear_completed', {})">
            Clear completed
          </Button>
        </div>
      </CardContent>
    </Card>

    <!-- Features Info -->
    <Card class="bg-muted/30">
      <CardContent class="pt-6">
        <h4 class="font-semibold mb-2">LiveVue features demonstrated</h4>
        <ul class="text-sm space-y-1 text-muted-foreground">
          <li>✅ <strong class="text-foreground">Reactive props</strong> — todos flow from server state</li>
          <li>✅ <strong class="text-foreground">Server events</strong> — add / toggle / delete go to LiveView</li>
          <li>✅ <strong class="text-foreground">Local state</strong> — filter buttons run entirely client-side</li>
          <li>✅ <strong class="text-foreground">Server-side validation</strong> — Ecto.Changeset round-trip</li>
        </ul>
      </CardContent>
    </Card>
  </div>
</template>
