# Teaching Methodology

How Fluent teaches, independent of the surface it teaches through. The CLI skills and the
macOS app both follow this document; `LEARNING_SYSTEM.md` covers only how a terminal
session is run.

Nothing here may name a file, a database, a slash command, or a turn of conversation.
Those belong to a surface; this is what is true for all of them.

## Core principles

1. **Active Recall**
   - Always ask before showing answers
   - Force learner to retrieve from memory
   - Increases retention by 200-300%

2. **Spaced Repetition (SM-2 Algorithm)**
   - Review intervals based on performance
   - Prevents forgetting curve
   - Optimizes long-term retention

3. **Immediate Feedback**
   - Correct within seconds
   - Explain WHY it's wrong
   - Show correct version immediately

4. **Interleaving**
   - Mix different topics in same session
   - Don't drill one pattern for 20 minutes
   - Improves discrimination ability

5. **Comprehensible Input (i+1)**
   - Slightly above current level
   - Challenging but achievable
   - Aim for 60-70% success rate

6. **Desirable Difficulty**
   - Start easy → medium → hard
   - Adjust based on success rate
   - Too easy = no learning, too hard = frustration

---

## Choosing difficulty

**Algorithm:**
```python
def select_difficulty(mastery_level, recent_accuracy):
    if mastery_level <= 1:
        return "easy"  # 70%+ success rate expected
    elif mastery_level == 2:
        return "medium" if recent_accuracy > 0.60 else "easy"
    elif mastery_level == 3:
        return "medium" if recent_accuracy > 0.70 else "medium"
    elif mastery_level >= 4:
        return "hard" if recent_accuracy > 0.80 else "medium"
```

## Exercise types by skill

**Writing:**
1. Sentence completion (fill in blanks)
2. Translation (Native Language → Target Language)
3. Error correction (find and fix mistakes)
4. Full email/letter writing
5. Sentence reordering

**Speaking:** (typed responses, simulate conversation)
1. Answer questions about yourself
2. Describe a picture/situation
3. Role-play scenarios (booking appointment, asking directions)
4. Pronunciation drills (type phonetically)

**Vocabulary:**
1. Flashcard-style (Target Language → Native Language)
2. Reverse (Native Language → Target Language)
3. Context clues (sentence with blank)
4. Word associations
5. Synonym/antonym matching

**Reading:**
1. Short text with comprehension questions
2. Fill in missing words in a paragraph
3. True/False questions
4. Summarization

**Listening:** (a prompt the learner hears rather than reads)
1. Transcribe what was said
2. Answer a comprehension question about it
3. Pick the phrase that was spoken, from options that differ in one sound
4. Numbers, prices and times, which are the ones with real-world cost

Listening carries the most transfer to actually using the language and is the
easiest skill to skip, because every other exercise type works on the page. A
lesson that never asks the learner to hear anything is not a balanced lesson.

## Error severity

When showing corrections, indicate severity:
- 🔴 **CRITICAL**: Major grammar errors that break communication
- 🟡 **MODERATE**: Noticeable but understandable errors
- 🟢 **MINOR**: Spelling errors (low priority for A2 exam)

---

## Quality checks

**Before responding, verify:**
- [ ] Did I read the latest learner-profile.json?
- [ ] Did I check spaced-repetition queue?
- [ ] Am I presenting ONE question at a time?
- [ ] Will I provide immediate feedback after their answer?
- [ ] Am I using the learner's name (from profile)?
- [ ] Am I being encouraging and fun?
- [ ] Will I update ALL databases after this session?
- [ ] Am I following evidence-based learning principles?

---
