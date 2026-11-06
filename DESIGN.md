# DESIGN.md — Product Website Design Constitution

> A reusable design system for AI coding agents.
>
> **Primary goal:** Build interfaces that feel intentionally designed by a strong product designer—not generic AI-generated SaaS pages.
>
> **Core principle:** The agent must make deliberate visual and interaction decisions. Do not default to common AI/SaaS patterns merely because they are easy to generate.

---

# 0. DESIGN NORTH STAR

Every website built under this document should feel:

- intentional
- premium
- calm
- technically credible
- visually coherent
- product-focused
- distinctive
- restrained
- fast
- accessible
- responsive

The interface should communicate **confidence without visual noise**.

Avoid the visual language of generic AI-generated websites:

- excessive gradients
- purple/blue “AI” glow
- random glassmorphism
- giant rounded cards everywhere
- excessive shadows
- floating blobs
- meaningless abstract 3D objects
- emoji-heavy UI
- stock-photo hero sections
- generic “AI-powered / revolutionary / next-generation” copy
- unnecessary badges
- excessive pill-shaped components
- every section having a different visual treatment
- huge empty sections that contain no useful information
- fake dashboard screenshots
- decorative elements that do not support the product

If a visual element does not improve **understanding, hierarchy, interaction, branding, or emotion**, remove it.

---

# 1. DESIGN PHILOSOPHY

## 1.1 Design before decoration

Do not start by adding effects.

First establish:

1. information hierarchy
2. content structure
3. navigation
4. primary user action
5. spacing system
6. typography
7. component system
8. responsive behavior
9. motion
10. decorative details

Decoration comes last.

---

## 1.2 Every page needs a visual idea

Before implementing a page, determine:

- What is the page trying to communicate?
- What is the primary action?
- What should the user notice first?
- What is the emotional tone?
- What makes this product visually recognizable?

Do not produce a page that is merely:

`Navbar → Hero → 3 Cards → Feature Grid → Testimonials → Pricing → FAQ → Footer`

unless that structure genuinely fits the product.

---

## 1.3 Avoid template gravity

AI agents tend to converge toward familiar layouts.

Do not automatically generate:

- centered hero + gradient text
- three feature cards
- “trusted by” logo wall
- testimonial carousel
- generic pricing cards
- huge rounded containers
- CTA repeated in every section

Use a pattern only when it serves the content.

---

# 2. VISUAL IDENTITY

## 2.1 Establish a visual system before coding

Create a small design token system.

Example:

```css
:root {
  --background: #0a0a0a;
  --surface: #111111;
  --surface-elevated: #171717;

  --text-primary: #f5f5f5;
  --text-secondary: #a3a3a3;
  --text-muted: #737373;

  --border: rgba(255, 255, 255, 0.10);
  --border-strong: rgba(255, 255, 255, 0.18);

  --accent: #ffffff;

  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 16px;

  --space-unit: 4px;
}
```

These values are examples, not mandatory values.

The actual product should receive its own visual identity.

---

# 3. COLOR

## 3.1 Use a restrained palette

Prefer:

- one dominant background
- one primary text color
- one secondary text color
- one border color
- one accent color
- semantic colors for success/warning/error

A strong monochrome design is often better than a rainbow palette.

---

## 3.2 Avoid gradient addiction

Gradients are allowed only when they have a clear design purpose.

Do NOT automatically use:

```css
background: linear-gradient(...);
```

on:

- hero headings
- buttons
- cards
- backgrounds
- borders
- every section

A gradient should be a deliberate brand element, not an AI default.

---

## 3.3 Dark mode

If using dark mode:

- avoid pure `#000` everywhere
- use multiple dark surfaces
- maintain clear contrast
- use borders subtly
- avoid excessive glow
- avoid making every element look like a floating glass panel

Good dark interfaces often use **layers**, not effects.

Example:

```text
BACKGROUND
    ↓
SURFACE
    ↓
ELEVATED SURFACE
    ↓
CONTENT
```

---

# 4. TYPOGRAPHY

Typography is one of the primary design tools.

## 4.1 Hierarchy

A typical hierarchy:

```text
Display
↓
H1
↓
H2
↓
H3
↓
Body
↓
Secondary
↓
Metadata
```

Do not make everything large.

Large text should create hierarchy.

---

## 4.2 Display typography

Hero headlines should generally be:

- concise
- high contrast
- carefully line-broken
- visually dominant
- readable

Avoid unnecessarily long marketing headlines.

Bad:

> Revolutionizing the future of next-generation AI-powered productivity for everyone.

Better:

> Work at the speed of thought.

The exact copy depends on the product.

---

## 4.3 Font selection

Choose fonts intentionally.

Prefer:

- modern sans-serif
- neutral grotesk
- technical monospace for metadata/code
- distinctive display type only when appropriate

Do not randomly combine 3–5 fonts.

Maximum recommended system:

```text
Primary font
+
Optional monospace
```

---

## 4.4 Line length

Long paragraphs should not span the entire viewport.

Use readable measure:

```css
max-width: 65ch;
```

for text-heavy content.

---

# 5. LAYOUT

## 5.1 Use a consistent grid

Desktop layouts should generally use a constrained content width.

Example:

```css
.container {
  width: min(100% - 40px, 1280px);
  margin-inline: auto;
}
```

Adjust based on the product.

---

## 5.2 Whitespace is structural

Whitespace should establish hierarchy.

Do not add whitespace simply because the page needs to look “premium.”

Every large empty area should have a reason:

- separating concepts
- emphasizing a headline
- slowing the reading rhythm
- creating visual focus

---

## 5.3 Break the grid intentionally

Not every section must be symmetrical.

Use:

- asymmetric layouts
- editorial compositions
- full-width sections
- offset elements
- controlled overlap

when they improve hierarchy.

But do not create asymmetry randomly.

---

# 6. NAVIGATION

Navigation should be simple.

Typical structure:

```text
Logo

Product
Solutions
Resources
Pricing

                    Login
                    Primary CTA
```

Rules:

- keep the number of primary navigation items low
- avoid giant dropdown menus unless necessary
- make the active state obvious
- preserve consistent spacing
- mobile navigation must be designed, not merely collapsed

The navbar should not compete with the hero.

---

# 7. HERO SECTION

The hero is not an advertisement.

It should immediately answer:

1. What is this?
2. Who is it for?
3. Why should I care?
4. What can I do next?

Recommended structure:

```text
Small contextual label

Clear headline

One concise explanation

Primary action   Secondary action

Product visual / demonstration
```

But the composition can vary.

Do not automatically use a centered hero.

---

# 8. PRODUCT-FIRST DESIGN

Whenever possible, **show the product**.

Prefer:

- interactive demos
- real UI
- code
- diagrams
- workflows
- real data
- product screenshots
- system visualizations

over:

- abstract blobs
- fake futuristic graphics
- meaningless 3D shapes

For developer products, code and architecture can be part of the visual identity.

For consumer products, show the actual experience.

---

# 9. COMPONENT DESIGN

## 9.1 Components need hierarchy

Not every component should look equally important.

Use visual hierarchy:

```text
Primary
Secondary
Tertiary
Metadata
```

---

## 9.2 Cards

Cards are useful, but should not become the default container for everything.

Avoid:

```text
┌──────────────┐
│ Icon         │
│              │
│ Title        │
│ Description  │
│              │
└──────────────┘
```

repeated 9 times.

Instead, vary composition where appropriate:

- horizontal feature rows
- editorial sections
- split layouts
- timelines
- comparison tables
- code blocks
- diagrams
- inline statistics

---

## 9.3 Borders

Use borders to define structure.

Prefer subtle borders over heavy shadows.

Example:

```css
border: 1px solid rgba(255,255,255,.10);
```

Do not put borders around every element.

---

## 9.4 Border radius

Choose a radius system and remain consistent.

Example:

```text
6px  → small controls
10px → buttons / inputs
16px → major containers
```

Do not make every object extremely rounded.

Avoid:

```text
EVERYTHING = rounded-full
```

unless the product's identity specifically calls for it.

---

# 10. BUTTONS

Buttons should communicate hierarchy.

Recommended:

```text
Primary
Secondary
Tertiary / Text
```

Example:

```text
[ Start building ]

[ View documentation ]

Learn more →
```

Avoid:

- giant gradients
- excessive shadows
- animated glowing borders
- unnecessary icons
- 4 competing primary CTAs

A button should look clickable without screaming for attention.

---

# 11. ICONOGRAPHY

Use icons only when they improve comprehension.

Preferred:

- Lucide
- Phosphor
- another consistent icon system

Do not mix unrelated icon libraries.

Do not use icons as decoration next to every heading.

Avoid:

```text
🚀 Build
⚡ Fast
🤖 AI
🔒 Secure
```

unless the product genuinely has a playful visual language.

---

# 12. IMAGES & GRAPHICS

Use visuals with purpose.

Good:

- product screenshots
- diagrams
- architecture
- custom illustrations
- photography that communicates the product
- technical visualizations

Bad:

- random Unsplash image
- generic person smiling at laptop
- AI-generated “futuristic robot”
- random abstract gradient sphere

If imagery is not necessary, omit it.

---

# 13. MOTION

Motion should communicate state or create rhythm.

Good uses:

- hover feedback
- page transitions
- reveal animations
- loading states
- progress
- expanding/collapsing content
- subtle navigation transitions

Avoid:

- everything flying in
- constant floating
- excessive parallax
- bouncing buttons
- continuous background animation
- animation that delays interaction

---

## 13.1 Motion principles

Use:

```text
fast → interaction feedback
medium → component transitions
slow → atmospheric transitions
```

Respect:

```css
@media (prefers-reduced-motion: reduce) {
  /* disable non-essential motion */
}
```

---

# 14. MICROINTERACTIONS

Small details create polish.

Examples:

- button hover changes subtly
- navigation indicator moves smoothly
- copied code confirms visually
- selected tab becomes obvious
- loading states communicate progress
- inputs show clear focus
- errors explain how to recover

Microinteractions should feel **intentional, not entertaining**.

---

# 15. RESPONSIVE DESIGN

Do not design desktop first and simply shrink it.

Design:

```text
Mobile
Tablet
Desktop
Large Desktop
```

Mobile should be a deliberate composition.

Rules:

- avoid horizontal overflow
- preserve hierarchy
- reduce decorative complexity
- maintain readable typography
- keep touch targets large enough
- redesign navigation
- stack content intelligently
- preserve the primary action

---

# 16. ACCESSIBILITY

Accessibility is part of design quality.

Must include:

- semantic HTML
- keyboard navigation
- visible focus states
- sufficient color contrast
- alt text for meaningful images
- labels for inputs
- reduced-motion support
- accessible interactive states

Do not use color alone to communicate state.

---

# 17. CONTENT DESIGN

The interface and copy are one system.

Avoid generic AI copy such as:

> Unlock the power of AI.

> Transform your workflow.

> Supercharge productivity.

> The future of work is here.

Instead communicate concrete value.

Prefer:

> Analyze any GitHub repository in seconds.

over:

> Intelligent code analysis powered by AI.

Be specific.

---

# 18. DATA & TECHNICAL PRODUCTS

For developer tools, AI infrastructure, analytics, or technical products:

Lean into the technical identity.

Use:

- monospace labels
- command-line snippets
- architecture diagrams
- API examples
- system status
- metrics
- logs
- structured data
- technical terminology

But maintain readability.

The site should feel like the **product itself**, not a marketing wrapper around it.

---

# 19. EMPTY STATES

Never leave users with a dead blank screen.

A good empty state explains:

```text
What happened?
Why is it empty?
What can I do next?
```

Example:

```text
No repositories analyzed yet.

Connect a repository to generate
your first architecture map.

[ Connect GitHub ]
```

---

# 20. LOADING STATES

Never use arbitrary spinners everywhere.

Use contextual feedback.

Examples:

```text
Analyzing repository...
Scanning 143 files
Building dependency graph
```

For long-running processes, show progress where possible.

---

# 21. ERROR STATES

Errors should be:

- clear
- specific
- actionable
- calm

Bad:

> Something went wrong.

Better:

> GitHub authorization expired.
> Reconnect your account to continue.

[ Reconnect GitHub ]

---

# 22. DASHBOARDS

Do not build dashboards as grids of random cards.

Start with:

1. primary user task
2. most important metric
3. current state
4. next action
5. supporting information

A dashboard should answer:

> “What do I need to know or do right now?”

---

# 23. LANDING PAGE STRUCTURE

There is no mandatory structure.

A possible flow:

```text
Navigation
↓
Hero
↓
Product demonstration
↓
Problem
↓
Solution
↓
Core capabilities
↓
Technical/product proof
↓
Use cases
↓
Social proof (only if real)
↓
Pricing / CTA
↓
Footer
```

Use only the sections the product needs.

---

# 24. SOCIAL PROOF

Never fabricate:

- customer logos
- testimonials
- user counts
- GitHub stars
- revenue
- performance statistics

If the product has no social proof yet, omit the section.

Authenticity > appearance.

---

# 25. DESIGNING FOR TRUST

Trust comes from:

- clear information
- transparent behavior
- coherent UI
- predictable interactions
- good typography
- strong accessibility
- real product evidence
- fast performance
- honest copy

Do not try to manufacture trust with:

- fake badges
- fake statistics
- “trusted by” logos that are not real
- excessive security icons

---

# 26. PERFORMANCE IS PART OF DESIGN

A beautiful site that feels slow is not a beautiful product.

Prefer:

- optimized images
- lazy loading
- minimal JavaScript
- efficient animations
- code splitting
- sensible dependencies
- proper caching
- no unnecessary third-party scripts

Avoid adding a library solely because it makes an animation easier.

---

# 27. TECH STACK DEFAULTS

When building a modern web product, prefer:

```text
Framework:
Next.js / React

Styling:
Tailwind CSS or well-structured CSS

Icons:
Lucide / Phosphor

Animation:
CSS first
Framer Motion only when useful

Fonts:
One primary family
Optional monospace

Images:
Optimized formats
Lazy loaded where appropriate
```

These are defaults, not requirements.

Use the project's existing stack when one already exists.

---

# 28. AI AGENT IMPLEMENTATION RULES

When implementing a website from this document, the AI agent MUST:

### Before coding

1. Inspect the existing repository.
2. Identify the current framework and styling system.
3. Reuse existing components where appropriate.
4. Identify existing brand assets.
5. Understand the product and target users.
6. Define the visual direction.
7. Establish design tokens.
8. Define the page hierarchy.

### During implementation

1. Build the layout first.
2. Establish typography.
3. Establish spacing.
4. Establish colors.
5. Build reusable components.
6. Add interaction states.
7. Add responsive behavior.
8. Add motion last.
9. Test the actual user flow.
10. Remove unnecessary visual elements.

### Before finishing

Check:

- mobile
- tablet
- desktop
- keyboard navigation
- focus states
- loading states
- empty states
- errors
- hover states
- responsive typography
- visual consistency
- performance

---

# 29. ANTI–AI-SLOP CHECKLIST

Before considering a page complete, ask:

### Visual

- Does this look like a template?
- Did I use a gradient just because AI websites commonly use gradients?
- Are there too many cards?
- Are there too many rounded containers?
- Are there unnecessary shadows?
- Are there unnecessary icons?
- Is there unnecessary decoration?
- Is the page visually repetitive?
- Does every section look the same?

### Content

- Is the copy specific?
- Does every section communicate something useful?
- Did I remove generic marketing language?
- Are claims factual?
- Are statistics real?

### Interaction

- Is the primary action obvious?
- Do controls provide feedback?
- Are loading/error/empty states designed?
- Does mobile feel intentional?

### Product identity

- Could this website belong to 100 other startups?
- What makes this interface recognizable?
- Does the visual language reflect the actual product?

If the answer to the last question is no, redesign.

---

# 30. THE "REMOVE 20%" RULE

After completing the interface:

**Remove approximately 20% of unnecessary visual elements.**

Look for:

- redundant text
- duplicate buttons
- unnecessary cards
- decorative shapes
- excessive labels
- unnecessary animations
- repeated CTAs
- excessive borders
- redundant sections

Good design often comes from subtraction.

---

# 31. FINAL DESIGN PRINCIPLE

Do not ask:

> “What does a modern website usually look like?”

Ask:

> “What should THIS product look like?”

The goal is not to make an impressive-looking website.

The goal is to make a product whose visual language feels:

**intentional, coherent, useful, distinctive, and unmistakably designed.**

---

# AGENT INSTRUCTION

When this `DESIGN.md` is provided to you, treat it as the project's **design constitution**.

You may adapt the exact colors, typography, layout, components, and visual direction to the product.

You MUST NOT blindly copy the examples.

You MUST preserve the underlying principles:

```text
Intentionality
+
Hierarchy
+
Restraint
+
Product-first visuals
+
Specific content
+
Consistent systems
+
Purposeful motion
+
Accessibility
+
Performance
=
Non-generic interface
```

When uncertain between:

```text
more decoration
vs.
more clarity
```

choose clarity.

When uncertain between:

```text
more components
vs.
simpler composition
```

choose the simpler composition.

When uncertain between:

```text
generic modern design
vs.
product-specific design
```

choose product-specific design.
