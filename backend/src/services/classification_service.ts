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
    originalCategory?: string | string[],
    fullContent?: string
  ): ClassificationResult {
    const titleLower = (title || '').toLowerCase();
    const descLower = (description || '').toLowerCase();
    const contentLower = (fullContent || '').toLowerCase();
    const fullText = `${titleLower} ${descLower} ${contentLower}`;

    const categoryScores: Map<AppCategory, number> = new Map();
    APP_CATEGORIES.forEach((cat) => categoryScores.set(cat, 0));

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

    // 1. Weighted Keyword Scoring across Title (weight 3), Description (weight 2), Content (weight 1)
    const categoryPatterns: Record<AppCategory, RegExp[]> = {
      Breaking: [
        /\b(breaking|urgent|alert|just in|flash news|bulletin|disaster|tragedy|state of emergency|explosion|massacre|earthquake|tsunami)\b/gi,
      ],
      Kenya: [
        /\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|kisumu|nyeri|machakos|ruto|raila|gachagua|knec|kuccps|tsc|kdf|county|counties|shilling|sacco|matatu|huduma|bodaboda)\b/gi,
      ],
      Africa: [
        /\b(africa|african|uganda|tanzania|rwanda|ethiopia|nigeria|south africa|somalia|sudan|south sudan|ghana|zimbabwe|zambia|malawi|mozambique|congo|drc|senegal|mali|burkina faso|angola|cameroon|egypt|morocco|ecowas|au|african union|eac|sadc|igad|kampala|dodoma|kigali|addis ababa|lagos|cairo|johannesburg|accra)\b/gi,
      ],
      World: [
        /\b(world|global|international|un|united nations|europe|us|usa|china|russia|ukraine|middle east|gaza|israel|foreign|nato|eu|european union|washington|london|beijing|tokyo)\b/gi,
      ],
      Politics: [
        /\b(politics|political|government|election|elections|parliament|senate|president|presidential|minister|governor|court|supreme court|judiciary|law|policy|policies|diplomacy|bipartisan|mp|mps|lawmaker|lawmakers|bill|cabinet|opposition|ruto|raila|gachagua|kenyat|biden|trump|putin|zelensky|white house|kremlin|diplomat|sanctions|treaty|veto|ballot|vote|voting|campaign)\b/gi,
      ],
      Business: [
        /\b(business|economy|economic|market|markets|stocks|crypto|bitcoin|trade|trading|finance|financial|bank|banking|revenue|profit|loss|startup|investors|investment|gdp|inflation|central bank|cbk|tax|taxes|taxation|tariff|currency|shilling|dollar|interest rates|commerce|corporate|sales|exporter|importer|treasury)\b/gi,
      ],
      Technology: [
        /\b(technology|tech|software|hardware|ai|artificial intelligence|machine learning|cyber|cybersecurity|google|apple|microsoft|nvidia|meta|app|apps|smartphone|cloud|gadget|code|coding|digital|mobile|internet|telecom|safaricom|airtel|5g|fintech|semiconductor|microchip|robotics|automation|electric vehicle|ev|satellites|space-x|openai|chatgpt|computing|startups?)\b/gi,
      ],
      Science: [
        /\b(science|scientific|scientist|scientists|space|nasa|astronomy|planet|planets|physics|biology|chemistry|research|discovery|laboratory|lab|dinosaur|fossil|evolution|genetics|solar system|telescope|astrophysics|quantum|exoplanet|genome|particle)\b/gi,
      ],
      Education: [
        /\b(education|university|universities|school|schools|college|colleges|student|students|examination|examinations|exam|exams|scholarship|scholarships|knec|kuccps|curriculum|research|teacher|teachers|academic|academics|learning|tuition|kcse|kcpe|cbc|graduates|graduation|campus|lecture|professor)\b/gi,
      ],
      Health: [
        /\b(health|healthcare|hospital|doctor|doctors|nurse|nurses|medicine|medical|virus|disease|diseases|vaccine|vaccines|mental health|who|cancer|treatment|outbreak|epidemic|pandemic|clinic|clinical|patient|patients|pharma|pharmaceutical|surgery|surgical|wellness|infection|therapy|hygiene)\b/gi,
      ],
      Nature: [
        /\b(nature|wildlife|conservation|forest|forests|biodiversity|climate|environment|environmental|park|parks|national park|ocean|oceans|pollution|ecosystem|flora|fauna|kws|kenya wildlife service|greenhouse|deforestation|carbon|species|natural habitat|reserve|marine)\b/gi,
      ],
      Culture: [
        /\b(culture|cultural|tradition|traditions|traditional|festival|festivals|heritage|museum|museums|religion|religious|language|languages|arts|art|fashion|cultural events|customs|folklore|tribal|indigenous|crafts|exhibition|ritual|heritage site)\b/gi,
      ],
      Entertainment: [
        /\b(entertainment|movie|movies|film|films|music|musical|celebrity|celebrities|actor|actress|cinema|hollywood|nollywood|song|songs|album|show|shows|concert|artist|artists|grammy|oscar|emmy|theater|streamer|streaming|netflix)\b/gi,
      ],
      Sports: [
        /\b(sports|sport|football|soccer|premier league|epl|champions league|ucl|nba|basketball|athletics|marathon|olympics|tennis|golf|rugby|match|tournament|goal|trophy|game|player|team|league|coach|stadium|cup|championship|club|transfer|striker|defender|wrc|rally|boxing|racing|f1|formula 1|harambee stars|kpl|afcon|world cup|cricket|chelsea|arsenal|manchester|liverpool|real madrid|barcelona)\b/gi,
      ],
    };

    for (const cat of APP_CATEGORIES) {
      const patterns = categoryPatterns[cat];
      if (!patterns) continue;

      let score = categoryScores.get(cat) || 0;

      for (const rx of patterns) {
        const titleMatches = titleLower.match(rx);
        if (titleMatches) score += titleMatches.length * 3;

        const descMatches = descLower.match(rx);
        if (descMatches) score += descMatches.length * 2;

        if (contentLower) {
          const contentMatches = contentLower.match(rx);
          if (contentMatches) score += contentMatches.length * 1;
        }
      }

      categoryScores.set(cat, score);
    }

    // 2. Filter Genuine Relevant Categories (Score Threshold: >= 2, or >= 1 with title match/provider boost)
    const eligibleEntries = Array.from(categoryScores.entries())
      .filter(([_, score]) => score >= 2)
      .sort((a, b) => b[1] - a[1]);

    const sortedCategories = eligibleEntries.map((e) => e[0]);

    // Fallback if no category reached score threshold >= 2
    let primaryCategory: AppCategory;
    if (sortedCategories.length > 0) {
      primaryCategory = sortedCategories[0];
    } else {
      // Find highest score even if < 2, or default to World
      const allSorted = Array.from(categoryScores.entries())
        .sort((a, b) => b[1] - a[1]);
      primaryCategory = (allSorted.length > 0 && allSorted[0][1] > 0) ? allSorted[0][0] : 'World';
    }

    let secondaryCategories: AppCategory[] = sortedCategories.filter((c) => c !== primaryCategory);

    // Topic vs Geo Swap: If Kenya or Africa is top scored, but another strong topic category exists, set topic as primary
    if ((primaryCategory === 'Kenya' || primaryCategory === 'Africa') && secondaryCategories.length > 0) {
      const topicCategory = secondaryCategories.find((c) => c !== 'Kenya' && c !== 'Africa');
      if (topicCategory) {
        secondaryCategories = [primaryCategory, ...secondaryCategories.filter((c) => c !== topicCategory)];
        primaryCategory = topicCategory;
      }
    }

    // Determine Regional Priority & ensure regional tag is in secondaryCategories if applicable
    const regionalInfo = ClassificationService.determineRegionPriority(fullText);

    if (regionalInfo.regionPriority === 'Kenya' && primaryCategory !== 'Kenya' && !secondaryCategories.includes('Kenya')) {
      secondaryCategories.push('Kenya');
    } else if (
      (regionalInfo.regionPriority === 'Africa' || regionalInfo.regionPriority === 'East Africa') &&
      primaryCategory !== 'Africa' &&
      !secondaryCategories.includes('Africa')
    ) {
      secondaryCategories.push('Africa');
    }

    // Remove duplicates and primary category from secondaryCategories
    secondaryCategories = Array.from(new Set(secondaryCategories)).filter((c) => c !== primaryCategory);

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
    originalCategory?: string | string[],
    fullContent?: string
  ): AppCategory {
    return ClassificationService.classifyDetailed(title, description, originalCategory, fullContent).primaryCategory;
  }

  /**
   * Regional priority evaluator
   * Highest: Kenya (4) -> East Africa (3) -> Africa (2) -> World (1)
   */
  public static determineRegionPriority(text: string): {
    regionPriority: RegionPriority;
    regionScore: number;
  } {
    if (/\b(kenya|kenyan|nairobi|mombasa|nakuru|eldoret|laikipia|kisumu|nyeri|machakos|ruto|raila|gachagua|knec|kuccps|shilling|county)\b/i.test(text)) {
      return { regionPriority: 'Kenya', regionScore: 4 };
    }

    if (/\b(uganda|tanzania|rwanda|burundi|south sudan|east africa|eac|kampala|dodoma|kigali|bujumbura|juba)\b/i.test(text)) {
      return { regionPriority: 'East Africa', regionScore: 3 };
    }

    if (/\b(africa|african|nigeria|south africa|ethiopia|ghana|somalia|sudan|cairo|lagos|johannesburg|au|african union|ecowas)\b/i.test(text)) {
      return { regionPriority: 'Africa', regionScore: 2 };
    }

    return { regionPriority: 'World', regionScore: 1 };
  }
}
