# Design System & UI/UX Specification

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Version:** 1.0.0  
**Design Theme:** Cloud-Native Modern Minimalist  
**Target Resolution:** Responsive (Mobile 360px to Ultrawide 2560px)  

---

## 1. Design Philosophy & Aesthetic Vision

The interface is engineered around the **Cloud-Native Modern Minimalist** philosophy. It prioritizes:
- **Instant Clarity:** Visual indicators clearly communicate live system state (API health, database connectivity) alongside user data.
- **High Information Density with Generous Breathing Room:** Clean card-based layouts with crisp typography, balanced whitespace, and subtle border hierarchy.
- **Tactile Interactivity:** Micro-interactions (hover elevations, pulsing status dots, smooth modal backdrop blurs) that deliver a premium, responsive feel.

---

## 2. Color Palette & Semantic Tokens

The color system uses refined slate neutrals paired with a vibrant royal blue primary accent and clear semantic feedback colors:

```text
[ Primary Palette ]
#2563eb (Blue 600)   ──> Primary Brand Accent / Action Buttons
#1d4ed8 (Blue 700)   ──> Primary Hover State
#eff6ff (Blue 50)    ──> Light Surface Tint / Active Hover Highlights

[ Neutrals & Surfaces ]
#f8fafc (Slate 50)   ──> App Canvas Background
#ffffff (White)      ──> Card Surfaces, Modals, Inputs
#e2e8f0 (Slate 200)  ──> Primary Dividers & Subtle Borders
#0f172a (Slate 900)  ──> High-Contrast Primary Typography
#64748b (Slate 500)  ──> Muted Secondary Labels & Subtitles
#94a3b8 (Slate 400)  ──> Icons & Search Placeholders

[ Semantic Status Indicators ]
#10b981 (Emerald 500)──> Healthy State / Active Connection Dot
#ecfdf5 (Emerald 50) ──> Healthy Status Pill Background
#065f46 (Emerald 800)──> Healthy Status Text
#ef4444 (Red 500)    ──> Danger / Unhealthy Dot / Delete Actions
#fef2f2 (Red 50)     ──> Danger Status Pill Background / Alert Surface
#991b1b (Red 800)    ──> Error Alert Text
```

### CSS Custom Properties Mapping
```css
:root {
  --bg-main: #f8fafc;
  --bg-card: #ffffff;
  --border-color: #e2e8f0;
  --border-focus: #3b82f6;
  --text-main: #0f172a;
  --text-muted: #64748b;
  --text-faint: #94a3b8;
  --primary: #2563eb;
  --primary-hover: #1d4ed8;
  --primary-light: #eff6ff;
  --danger: #ef4444;
  --danger-hover: #dc2626;
  --danger-light: #fef2f2;
  --success: #10b981;
  --success-light: #ecfdf5;
  --success-text: #065f46;
}
```

---

## 3. Typography Hierarchy

The design adopts **Plus Jakarta Sans**, a modern geometric grotesque typeface optimized for screen legibility and digital interfaces.

* **Primary Font Family:** `'Plus Jakarta Sans', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
* **Fallback Stack:** Native system sans-serif

| Element | Size | Weight | Line Height | Letter Spacing | Purpose |
|---|---|---|---|---|---|
| **App Title** | `1.5rem` (24px) | `700` (Bold) | `1.2` | `-0.02em` | Main application brand header. |
| **Subtitle** | `0.85rem` (13.6px) | `500` (Medium) | `1.4` | `0` | Contextual architectural label. |
| **Modal Header** | `1.25rem` (20px) | `700` (Bold) | `1.3` | `-0.01em` | Create / Edit modal title. |
| **Card Title** | `1.1rem` (17.6px) | `700` (Bold) | `1.35` | `0` | Note headline. |
| **Body Content** | `0.925rem` (14.8px) | `400` (Regular) | `1.6` | `0` | Note text, input fields, form labels. |
| **Status Pills** | `0.8rem` (12.8px) | `600` (Semi-Bold) | `1.0` | `0` | Health check indicator badges. |
| **Timestamps / IDs** | `0.775rem` (12.4px) | `500` (Medium) | `1.0` | `0` | Card metadata footer. |

---

## 4. Component Geometry & Elevation

### 4.1 Border Radius Tokens
- **`--radius-sm` (6px):** Action icons, buttons, and inner tags.
- **`--radius-md` (10px):** Form inputs, primary action buttons, search bars.
- **`--radius-lg` (16px):** Note cards, modal dialogs, and state containers.
- **`9999px` (Pill):** Health check status pills.

### 4.2 Elevation & Shadow Hierarchy
- **`--shadow-sm`:** `0 1px 2px 0 rgb(0 0 0 / 0.05)` — Rest state for cards and inputs.
- **`--shadow-md`:** `0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)` — Hover state for cards.
- **`--shadow-lg`:** `0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)` — Floating modal dialogs.

---

## 5. Core Component Design Patterns

### 5.1 System Health Indicators (Header Pills)
- Located in the top header beside the brand title.
- Displays instantaneous connectivity for both compute (`API: Healthy (200)`) and database (`DB: Connected`).
- Features a live glowing dot (`box-shadow: 0 0 6px rgba(16, 185, 129, 0.6)`) and a circular refresh trigger.

### 5.2 Responsive Notes Grid
- Implements CSS Grid with fluid wrapping:
  ```css
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 1.5rem;
  ```
- Each card displays title, edit/delete actions, text body, and formatted timestamp footer.
- Hover transition: `transform: translateY(-2px)` with subtle border highlight.

### 5.3 Modal Form Dialog
- Accessible modal centered on screen with backdrop blur:
  ```css
  background-color: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(4px);
  ```
- Smooth enter animation (`scaleUp 0.2s cubic-bezier(0.16, 1, 0.3, 1)`).
- Input focus rings: `box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.15)`.

### 5.4 Empty & Loading States
- Loading: Minimalist CSS spinning ring (`animation: spin 0.8s linear infinite`).
- Empty State: Clean bordered dashed container with emoji illustration and a direct call-to-action button (`Create First Note`).

---

## 6. Responsive Breakpoints

| Breakpoint | Target Devices | Layout Adaptations |
|---|---|---|
| **$< 640px$** | Mobile Phones | Header stacks vertically. Health badges shift below logo. Search bar and New Note button wrap to full width. Single column card view. |
| **$641px - 1024px$** | Tablets / Small Laptops | 2-column note card grid. Search bar spans flexible width. |
| **$> 1025px$** | Desktops & Monitors | 3-column note card grid. Max application container clamped to `1200px` with centered alignment. |
