# Handoff to implementation

**Chosen variant:** Option B + A (Compact Switcher with Empty State)

**Screens / flows:**
- **HomeDashboardView.swift:** Redesign layout to remove the permanent Welcome header. Move the Connection Status cards to the top. The Profile List should take up most of the space.
- **Empty State:** If `accountStore.accounts.isEmpty`, show the "Chào mừng" and the "Hướng dẫn nhanh" (Quick Guide) centered beautifully.
- **Populated State:** Hide the guide completely when profiles > 0.

**Tokens / components to reuse:**
- `ProfileRowView`, `StatusCard`, `GuideRow` are already built and good. Just rearrange them.

**Out of scope:**
- Modifying how profiles are added/edited.
- Changing `AccountStore` logic.

**Agent prompt stub:**

```
Implement the "Compact Switcher" variant in HomeDashboardView.swift.
If `accounts.isEmpty`, display the Welcome Header and the Quick Guide as an empty state.
If `!accounts.isEmpty`, remove the Welcome Header and Quick Guide. Show only the Connection Status and Profile List, filling the available space.
```
