import { AppCategory, APP_CATEGORIES, RegionPriority } from '../models/news_article.model';

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
    const text = `${title} ${description}`.toLowerCase();

    const categoryScores: Map<AppCategory, number> = new Map();

    // 0. Boost explicit source categories (from NewsData / NewsAPI metadata)
    if (originalCategory) {
      const origCategories = Array.isArray(originalCategory)
        ? originalCategory
        : [originalCategory];
      for (const catStr of origCategories) {
        const lowerCat = catStr.toLowerCase();
        for (const appCat of APP_CATEGORIES) {
          if (
            lowerCat === appCat.toLowerCase() ||
            lowerCat.includes(appCat.toLowerCase()) ||
            appCat.toLowerCase().includes(lowerCat)
          ) {
            categoryScores.set(appCat, (categoryScores.get(appCat) || 0) + 5);
          }
        }
      }
    }

    // 1. Keyword rule checks with weights
    ClassificationService.scoreCategory(categoryScores, 'Kenya', text, [
      /\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|ruto|raila|gachagua|knec|tsc|kdf|county|counties|shilling|sacco|matatu|huduma|bodaboda)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Breaking', text, [
      /\b(breaking|urgent|alert|just in|flash|disaster|tragedy|state of emergency|explosion|massacre|earthquake|tsunami)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Africa', text, [
      /\b(africa|african|uganda|tanzania|rwanda|ethiopia|nigeria|south africa|somalia|sudan|south sudan|ghana|zimbabwe|zambia|malawi|mozambique|congo|drc|senegal|mali|burkina faso|angola|cameroon|ecowas|au|african union|eac|sadc|igad|kampala|dodoma|kigali|addis ababa|lagos|cairo|johannesburg|accra)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Politics', text, [
      /\b(politics|political|government|election|elections|parliament|senate|president|presidential|minister|governor|court|supreme court|judiciary|law|policy|policies|diplomacy|bipartisan|mp|mps|lawmaker|lawmakers|bill|cabinet|opposition|ruto|raila|gachagua|kenyat|biden|trump|putin|zelensky|white house|kremlin|diplomat|sanctions|treaty|veto|ballot|vote|voting|campaign)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Business', text, [
      /\b(business|economy|economic|market|markets|stocks|crypto|bitcoin|trade|trading|finance|financial|bank|banking|revenue|profit|loss|startup|investor|investors|investment|gdp|inflation|central bank|cbk|tax|taxes|taxation|tariff|currency|shilling|dollar|interest rates|commerce|corporate|sales|exporter|importer|treasury)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Technology', text, [
      /\b(tech|technology|software|hardware|ai|artificial intelligence|machine learning|cyber|cybersecurity|google|apple|microsoft|nvidia|meta|app|apps|smartphone|cloud|gadget|code|coding|digital|mobile|internet|telecom|safaricom|airtel|5g|fintech|semiconductor|microchip|robotics|automation|electric vehicle|ev|satellites|space-x|openai|chatgpt)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Sports', text, [
      /\b(sports|sport|football|soccer|premier league|epl|champions league|ucl|nba|basketball|athletics|marathon|olympics|tennis|golf|rugby|match|tournament|goal|trophy|game|player|team|league|coach|stadium|cup|championship|club|transfer|striker|defender|wrc|rally|boxing|racing|f1|formula 1|harambee stars|kpl|afcon|world cup|cricket|chelsea|arsenal|manchester|liverpool|real madrid|barcelona)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Health', text, [
      /\b(health|healthcare|hospital|doctor|doctors|nurse|nurses|medicine|medical|virus|disease|diseases|vaccine|vaccines|mental health|who|cancer|treatment|outbreak|epidemic|pandemic|clinic|clinical|patient|patients|pharma|pharmaceutical|surgery|surgical|wellness|infection)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Education', text, [
      /\b(education|school|schools|university|universities|student|students|teacher|teachers|college|academic|academics|learning|curriculum|exam|exams|examination|kcse|kcpe|cbc|tuition|scholarship|scholarships|knec|tsc|headmaster|principal|graduates|graduation)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Entertainment', text, [
      /\b(entertainment|movie|movies|film|films|music|musical|celebrity|celebrities|actor|actress|cinema|hollywood|nollywood|song|songs|album|show|shows|concert|artist|artists|grammy|oscar|emmy|culture|fashion|lifestyle|theater|streamer|streaming|netflix)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'Science', text, [
      /\b(science|scientific|scientist|scientists|space|nasa|astronomy|planet|planets|physics|biology|chemistry|climate|environment|environmental|research|discovery|laboratory|lab|dinosaur|fossil|evolution|genetics|ecosystem|solar system|telescope)\b/gi,
    ]);

    ClassificationService.scoreCategory(categoryScores, 'World', text, [
      /\b(world|global|international|un|united nations|europe|us|usa|asia|china|russia|ukraine|middle east|gaza|israel|foreign|nato|eu|european union)\b/gi,
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

