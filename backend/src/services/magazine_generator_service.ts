import { ViewerDocumentBuilder } from './viewer_document_builder';
import { NormalizedNews, StoryCluster } from '../models/news_article.model';
import { MagazineViewerDocument } from '../models/magazine_viewer.model';

export class MagazineGeneratorService {
  public static generateViewerDocument(
    article: NormalizedNews,
    imageKitUrl: string,
    cluster?: StoryCluster
  ): MagazineViewerDocument {
    return ViewerDocumentBuilder.buildViewerDocument(article, imageKitUrl, cluster);
  }
}
