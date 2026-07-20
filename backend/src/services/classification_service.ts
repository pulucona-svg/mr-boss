import { AppCategory, RegionPriority } from '../models/news_article.model';

export interface ClassificationResult {
  primaryCategory: AppCategory;
  secondaryCategories: AppCategory[];
  regionPriority: RegionPriority;
  regionScore: number;
}

export class ClassificationService {
  /**
   * Classifies an article into Primary Category, Secondary Categories, and Regional Priority.
   */
  public static classifyDetailed(
    title: string,
    description: string,
    originalCategory?: string | string[]
  ): ClassificationResult {
    const text = `${title} ${description} ${
      Array.isArray(originalCategory) ? originalCategory.join(' ') : originalCategory || ''
    }`.toLowerCase();

    const categoryScores: Map<AppCategory, number> = new Map();

    // 1. Keyword rule checks with weights
    ClassificationService.scoreCategory(categoryScores, 'Kenya', text, [
      /\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|ruto|raila|knec|tsc|kdf|county|shilling)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Breaking', text, [
      /\b(breaking|urgent|alert|just in|flash|disaster|tragedy|state of emergency)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Africa', text, [
      /\b(africa|african|uganda|tanzania|rwanda|ethiopia|nigeria|south africa|somalia|sudan|ghana|ecowas|au|african union)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Politics', text, [
      /\b(politics|political|government|election|parliament|senate|president|minister|governor|court|supreme court|law|policy|diplomacy|bipartisan)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Business', text, [
      /\b(business|economy|market|stocks|crypto|bitcoin|trade|finance|financial|bank|banking|revenue|profit|startup|investor|gdp|inflation)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Technology', text, [
      /\b(tech|technology|software|ai|artificial intelligence|cyber|cybersecurity|google|apple|microsoft|nvidia|app|smartphone|cloud|gadget|code)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Sports', text, [
      /\b(sports|football|soccer|premier league|champions league|nba|basketball|athletics|marathon|olympics|tennis|golf|rugby|match|tournament|goal|trophy)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Health', text, [
      /\b(health|hospital|doctor|medicine|medical|virus|disease|vaccine|mental health|who|cancer|treatment|healthcare|outbreak|clinic)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Education', text, [
      /\b(education|school|university|student|teacher|college|academic|learning|curriculum|exam|kcse|kcpe|tuition|scholarship)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Entertainment', text, [
      /\b(entertainment|movie|film|music|celebrity|actor|actress|cinema|hollywood|nollywood|song|album|show|concert|artist|grammy|oscar)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Science', text, [
      /\b(science|scientific|space|nasa|astronomy|planet|physics|biology|climate|environment|research|discovery|laboratory|dinosaur)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'World', text, [
      /\b(world|global|international|un|united nations|europe|us|asia|china|foreign)\b/gi,
    ]);

    // Determine sorted categories by match count/score
    const sortedCategories = Array.from(categoryScores.entries())
      .sort((a, b) => b[1] - a[1])
      .map((entry) => entry[0]);

    // Fallback if no categories matched
    let primaryCategory: AppCategory = sortedCategories.length > 0 ? sortedCategories[0] : 'World';
    let secondaryCategories: AppCategory[] = sortedCategories.slice(1);

    // If Kenya or Africa was top scored but topic category exists (e.g. Education + Kenya), set topic as primary & Kenya as secondary
    if ((primaryCategory === 'Kenya' || primaryCategory === 'Africa') && secondaryCategories.length > 0) {
      const topicCategory = secondaryCategories.find((c) => c !== 'Kenya' && c !== 'Africa');
      if (topicCategory) {
        // Swap topic to primary and keep Kenya/Africa in secondary
        secondaryCategories = [primaryCategory, ...secondaryCategories.filter((c) => c !== topicCategory)];
        primaryCategory = topicCategory;
      }
    }

    // Determine Regional Priority
    const regionalInfo = ClassificationService.determineRegionPriority(text);

    // Ensure regional category is present in secondaryCategories if applicable
    if (regionalInfo.regionPriority === 'Kenya' && !secondaryCategories.includes('Kenya') && primaryCategory !== 'Kenya') {
      secondaryCategories.push('Kenya');
    } else if (regionalInfo.regionPriority === 'Africa' && !secondaryCategories.includes('Africa') && primaryCategory !== 'Africa') {
      secondaryCategories.push('Africa');
    }

    return {
      primaryCategory,
      secondaryCategories,
      regionPriority: regionalInfo.regionPriority,
      regionScore: regionalInfo.regionScore,
    };
  }

  /**
   * Simple helper for single category lookup (backward compatibility)
   */
  public static classify(
    title: string,
    description: string,
    originalCategory?: string | string[]
  ): AppCategory {
    return ClassificationService.classifyDetailed(title, description, originalCategory).primaryCategory;
  }

  /**
   * Regional priority evaluator
   * Highest: Kenya (4) -> East Africa (3) -> Africa (2) -> World (1)
   */
  public static determineRegionPriority(text: string): {
    regionPriority: RegionPriority;
    regionScore: number;
  } {
    if (/\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|ruto|raila|shilling|county)\b/i.test(text)) {
      return { regionPriority: 'Kenya', regionScore: 4 };
    }

    if (/\b(uganda|tanzania|rwanda|burundi|south sudan|east africa|eac|kampala|dodoma|kigali)\b/i.test(text)) {
      return { regionPriority: 'East Africa', regionScore: 3 };
    }

    if (/\b(africa|african|nigeria|south africa|ethiopia|ghana|somalia|sudan|cairo|lagos|johannesburg|au|african union)\b/i.test(text)) {
      return { regionPriority: 'Africa', regionScore: 2 };
    }

    return { regionPriority: 'World', regionScore: 1 };
  }

  private static scoreCategory(
    map: Map<AppCategory, number>,
    category: AppCategory,
    text: string,
    regexes: RegExp[]
  ): void {
    let count = 0;
    for (const rx of regexes) {
      const matches = text.match(rx);
      if (matches) count += matches.length;
    }
    if (count > 0) {
      map.set(category, (map.get(category) || 0) + count);
    }
  }
}
