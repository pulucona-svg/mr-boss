export interface BaseCollector<T> {
  readonly name: string;
  fetchArticles(query?: string): Promise<T[]>;
}
