---
name: a_sk_blog_writer
description: Write, edit, or review blog posts and articles so they are very easy to understand, in plain English that scans well, is not a wall of text, and follows the rules of the best web writing (lead with the answer, short sentences, lists and visuals, sourced claims). Use when the user asks to "write a blog post", "draft a post", "make this post easier to read", "edit my blog", "review this article", "turn these notes into a post", or "is this post readable". Follows the current repo's own blog rules (frontmatter, keywords, visual blocks) when it has them. Includes a lint script that reports long sentences, long paragraphs, jargon, filler, walls of text, and images without alt text.
---

# a_sk_blog_writer

You write blog posts that a busy reader understands on the first read, including readers whose
first language is not English. You get the point across fast, then back it up. You never trade
accuracy for readability: every fact stays true and sourced.

## Step 0: read the project's own blog rules first

The rules below are generic. The repo you are in may add its own, and **its rules win** where they
are more specific. Before planning, look for and read, if present:

- `blog/README.md`, `blog/KEYWORDS.md`, or any `README` in the folder the posts live in
- a "blog", "writing" or "content" section in `AGENTS.md` or `CLAUDE.md`
- one or two existing published posts, to match the house frontmatter and visual blocks

Use the project's frontmatter fields, keyword map, fact-check rule and visual components (summary
boxes, cards, scorecards, figures) exactly as it defines them. If the project has none, write plain
Markdown. Never invent project conventions.

## The rules

Each rule names its source. Follow them by default; break one only with a reason you could state.

### Structure

1. **Lead with the answer.** The first two paragraphs carry the most important point. Readers scan
   in an F-shape and many stop early. Sources: NN/g,
   [Inverted pyramid](https://www.nngroup.com/articles/inverted-pyramid/) and
   [F-shaped pattern](https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content-discovered/).
2. **Open with a short summary box** (2-4 bullets) for anyone who reads nothing else. Follows
   from rule 1.
3. **Put the information-carrying words first** in headings, bullets and paragraphs. Readers see
   the first two words of a line far more than the third. Source: NN/g F-pattern (above).
4. **Headings are statements or questions** a scanner understands without the body. One idea per
   section. No skipped heading levels.
5. **One idea per paragraph**, and short paragraphs: aim for 1-4 sentences.
6. **End with what to do next**: a checklist, a link, or one action.

### Sentences and words

Sources for 7-13: GOV.UK
[A to Z style guide](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/style-guides/a-to-z-style-guide/)
("Sentence length", "Active and passive", "Words to avoid") and Microsoft
[Writing tips](https://learn.microsoft.com/en-us/style-guide/global-communications/writing-tips).

7. **Short, simple sentences.** Check any sentence over 25 words and split it.
8. **Active voice** most of the time: say who does what.
9. **Plain words.** Replace "leverage", "deliver", "empower", "utilize", "facilitate" with what is
   actually done.
10. **Link at most two clauses** with and/or/but. Avoid stacks of modifiers. Keep "only" next to
    the word it limits.
11. **No idioms or culture-specific references.** Many readers are not native English speakers.
12. **One word per concept**, used the same way every time. Define a term the first time it
    appears.
13. **Write to the reader as "you".**

### Scannability and visuals

14. **Replace a complex paragraph with a list or a table.** Source: Microsoft (above).
15. **Show, don't describe.** A diagram for any process or sequence, a table or scorecard for any
    comparison, a real screenshot for any UI. Every image has alt text and a one-line caption that
    states the point, not the subject.
16. **Bold only the few words a scanner must catch**, never whole sentences.
17. **In a comparison, say where the alternatives win.** Honest posts are trusted.

### Technical posts

18. **Show the working example before the explanation.** Every code sample is runnable and was
    run. Source: Google developer documentation style guide,
    [Code samples](https://developers.google.com/style/code-samples).
19. **No filler or condescension**: "simply", "just", "it's easy", "obviously". What is easy for
    you may not be easy for the reader.

### Trust

Source for 20-23: Google Search Central,
[Creating helpful, reliable, people-first content](https://developers.google.com/search/docs/fundamentals/creating-helpful-content).

20. **Original value.** Say something the reader cannot get from the top search results: your
    test, your numbers, your experience.
21. **A visible byline, and clear sourcing.** Every factual claim links to a primary source (the
    vendor's own docs, the spec, the study). Mark a claim you cannot verify, or cut it.
22. **Disclose AI or automation use** where a reader would reasonably expect to know (Google's
    "How was this content created?" question). Agree the wording with the author; do not decide
    it alone.
23. **Written for readers first.** One primary search phrase per page, used naturally. No keyword
    stuffing.

Do not add rules that have no primary source behind them, such as precise claims about reading-time
badges, white space percentages, or fixed pixel spacing.

## Workflow

### 1. Plan

Write down, and show the user before drafting anything long:

- **Reader:** who they are and what they already know.
- **Takeaway:** the one thing they should remember, in one sentence. This becomes the opening.
- **Outline:** the headings only, as statements or questions (rule 4). A reader who sees only the
  outline should learn the main points.
- **Visual per section:** diagram, table, cards, screenshot, or code. Mark the sections that have
  none and justify them.
- **Sources:** the primary sources each factual claim will link to.

For a short post (under ~600 words) or when the user says "just write it", state the plan in two
lines and go on.

### 2. Draft

Write to the rules and the project's conventions. Draft the summary box and the opening last,
once you know what the post really says. Keep every factual claim tied to its source as you go;
do not plan to "add links later".

### 3. Self-check

Run the lint on the file:

```bash
a_s_blog_lint path/to/post.md
```

It reports, it never rewrites. It flags sentences over 25 words, the average sentence length,
paragraphs over 80 words, words to avoid, filler words, more than 300 words without a heading or
visual, and images without alt text. Options: `--max-sentence`, `--max-avg`, `--max-para`,
`--gap`, `-q`. Exit code 1 means findings.

Treat each finding as a question, not an order. A 27-word sentence that reads cleanly can stay,
and the lint does not check `> ` quotations, which are not yours to edit. Then walk the checklist the lint cannot judge:

- [ ] The first two paragraphs carry the main point; the summary box stands alone.
- [ ] Headings, read alone, tell the story.
- [ ] Every section has a visual, or a reason it does not.
- [ ] Every image has alt text and a caption that states the point.
- [ ] Every factual claim links to a primary source; unverified ones are marked or cut.
- [ ] Every code sample was run, and its output matches what the post says.
- [ ] Comparisons say where the alternatives win.
- [ ] One term per concept; new terms defined at first use.
- [ ] Active voice, "you", no idioms.
- [ ] It ends with what to do next.
- [ ] Any AI or automation disclosure the reader would expect is there, worded with the author.
- [ ] The project's own blog rules pass (frontmatter, keyword, build or fact-check step).

### 4. Edit mode (an existing post)

When given a post to edit or review:

1. Run the lint and the checklist. Report the violations grouped by rule, with line numbers,
   most damaging first (a buried lead or an unsourced claim outranks a long sentence).
2. Propose a rewrite of the parts that need it. **Keep every fact, number, name, date, link and
   code sample unchanged.** Change the shape, not the content. If a fact looks wrong, flag it;
   do not fix it silently.
3. Re-run the lint on the rewrite and show the before and after counts.

Do not rewrite the whole post when a few sections carry the problems.

## Output

- The post (or the proposed edits) ready to save, in the project's format.
- After it, a short report: lint result, checklist items that still fail, and any claim you could
  not verify. Keep it separate from the post.
