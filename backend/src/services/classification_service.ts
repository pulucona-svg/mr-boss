import { AppCategory } from '../models/news_article.model';

export class ClassificationService {
  /**
   * Classifies an article into one of the 12 Mirror Laikipia categories based on keywords & metadata.
   */
  public static classify(
    title: string,
    description: string,
    originalCategory?: string | string[]
  ): AppCategory {
    const text = `${title} ${description} ${
      Array.isArray(originalCategory) ? originalCategory.join(' ') : originalCategory || ''
    }`.toLowerCase();

    // 1. Kenya Specific
    if (
      /\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|ruto|raila|knec|tsc|kdf|county|shilling)\b/i.test(
        text
      )
    ) {
      return 'Kenya';
    }

    // 2. Breaking News
    if (
      /\b(breaking|urgent|alert|just in|flash|disaster|tragedy|state of emergency)\b/i.test(
        text
      )
    ) {
      return 'Breaking';
    }

    // 3. Africa Regional
    if (
      /\b(africa|african|uganda|tanzania|rwanda|ethiopia|nigeria|south africa|somalia|sudan|ghana|ecowas|au|african union)\b/i.test(
        text
      )
    ) {
      return 'Africa';
    }

    // 4. Politics
    if (
      /\b(politics|political|government|election|parliament|senate|president|minister|governor|court|supreme court|law|policy|diplomacy|bipartisan)\b/i.test(
        text
      )
    ) {
      return 'Politics';
    }

    // 5. Business & Economy
    if (
      /\b(business|economy|market|stocks|crypto|bitcoin|trade|finance|financial|bank|banking|revenue|profit|startup|investor|gdp|inflation)\b/i.test(
        text
      )
    ) {
      return 'Business';
    }

    // 6. Technology
    if (
      /\b(tech|technology|software|ai|artificial intelligence|cyber|cybersecurity|google|apple|microsoft|nvidia|app|smartphone|cloud|gadget|code)\b/i.test(
        text
      )
    ) {
      return 'Technology';
    }

    // 7. Sports
    if (
      /\b(sports|football|soccer|premier league|champions league|nba|basketball|athletics|marathon|olympics|tennis|golf|rugby|match|tournament|goal|trophy)\b/i.test(
        text
      )
    ) {
      return 'Sports';
    }

    // 8. Health
    if (
      /\b(health|hospital|doctor|medicine|medical|virus|disease|vaccine|mental health|who|cancer|treatment|healthcare|outbreak|clinic)\b/i.test(
        text
      )
    ) {
      return 'Health';
    }

    // 9. Education
    if (
      /\b(education|school|university|student|teacher|college|academic|learning|curriculum|exam|kcse|kcpe|tuition|scholarship)\b/i.test(
        text
      )
    ) {
      return 'Education';
    }

    // 10. Entertainment
    if (
      /\b(entertainment|movie|film|music|celebrity|actor|actress|cinema|hollywood|nollywood|song|album|show|concert|artist|grammy|oscar)\b/i.test(
        text
      )
    ) {
      return 'Entertainment';
    }

    // 11. Science
    if (
      /\b(science|scientific|space|nasa|astronomy|planet|physics|biology|climate|environment|research|discovery|laboratory|dinosaur)\b/i.test(
        text
      )
    ) {
      return 'Science';
    }

    // 12. World / Global (Default)
    return 'World';
  }
}
