import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

// Utility used by shadcn-vue components to merge Tailwind classes
// while resolving conflicts (e.g., a later px-4 wins over an earlier px-2).
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
