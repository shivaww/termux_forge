/// RAG / semantic search service for TermuxForge.
///
/// [VectorMemoryService] indexes documents as vector embeddings, supports
/// chunking for code, docs, notes, and decisions, and provides context
/// retrieval with relevance ranking, compression, and citation tracking.
///
/// The default implementation uses a simple cosine-similarity store. In
/// production, swap in a dedicated vector DB (e.g. Qdrant, Pinecone) via
/// the [VectorStore] abstraction.
library;

import 'dart:math' as math;

import 'package:nexon/data/models/project_memory_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Vector Store Abstraction
// ---------------------------------------------------------------------------

/// A stored document with its embedding and metadata.
class VectorDocument {
  const VectorDocument({
    required this.id,
    required this.content,
    required this.embedding,
    this.metadata = const {},
    this.source,
    this.chunkIndex = 0,
  });

  /// Unique document identifier.
  final String id;

  /// Text content of the chunk.
  final String content;

  /// Embedding vector.
  final List<double> embedding;

  /// Arbitrary metadata.
  final Map<String, dynamic> metadata;

  /// Original source reference (file path, URL, etc.).
  final String? source;

  /// Index of this chunk within the source document.
  final int chunkIndex;
}

/// A search result with its similarity score.
class VectorSearchResult {
  const VectorSearchResult({
    required this.document,
    required this.score,
  });

  /// The matched document.
  final VectorDocument document;

  /// Cosine similarity score (0.0 – 1.0).
  final double score;
}

/// Context retrieval result with citations.
class CitedContext {
  const CitedContext({
    required this.context,
    required this.citations,
  });

  /// The assembled context string.
  final String context;

  /// Source references for each chunk used.
  final List<String> citations;
}

/// Abstract vector store. Swap implementations for different backends.
abstract class VectorStore {
  /// Add a document to the store.
  Future<void> add(VectorDocument document);

  /// Search for the [topK] most similar documents to [queryEmbedding].
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int topK = 10,
    double minScore = 0.0,
  });

  /// Remove a document by [id].
  Future<void> remove(String id);

  /// Return all stored documents.
  Future<List<VectorDocument>> getAll();
}

// ---------------------------------------------------------------------------
// In-Memory Vector Store
// ---------------------------------------------------------------------------

/// Simple in-memory [VectorStore] using brute-force cosine similarity.
class InMemoryVectorStore implements VectorStore {
  final Map<String, VectorDocument> _docs = {};

  @override
  Future<void> add(VectorDocument document) async {
    _docs[document.id] = document;
  }

  @override
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int topK = 10,
    double minScore = 0.0,
  }) async {
    final results = <VectorSearchResult>[];

    for (final doc in _docs.values) {
      final score = _cosineSimilarity(queryEmbedding, doc.embedding);
      if (score >= minScore) {
        results.add(VectorSearchResult(document: doc, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).toList();
  }

  @override
  Future<void> remove(String id) async => _docs.remove(id);

  @override
  Future<List<VectorDocument>> getAll() async => _docs.values.toList();

  /// Compute cosine similarity between two vectors.
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator == 0 ? 0.0 : dotProduct / denominator;
  }
}

// ---------------------------------------------------------------------------
// Chunking
// ---------------------------------------------------------------------------

/// Strategy for splitting content into chunks.
enum ChunkType {
  /// Source code — split by function / class boundaries.
  code,

  /// Documentation — split by headings / paragraphs.
  docs,

  /// Free-form notes — split by paragraph.
  notes,

  /// Architecture decisions — keep as single chunks.
  decisions,
}

/// A single chunk of text with metadata.
class TextChunk {
  const TextChunk({
    required this.content,
    required this.index,
    this.source,
  });

  final String content;
  final int index;
  final String? source;
}

// ---------------------------------------------------------------------------
// VectorMemoryService
// ---------------------------------------------------------------------------

/// RAG service that indexes, searches, and retrieves contextual information
/// using vector embeddings.
class VectorMemoryService {
  /// Creates a [VectorMemoryService] with the given [store] and optional
  /// [embedder] callback.
  VectorMemoryService({
    VectorStore? store,
    this.embedder,
  }) : _store = store ?? InMemoryVectorStore();

  final VectorStore _store;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Optional callback that generates an embedding vector from text.
  ///
  /// If null, a simple hash-based placeholder embedding is generated.
  /// In production, wire this to an embedding API (OpenAI, Cohere, etc.).
  final Future<List<double>> Function(String text)? embedder;

  // ---- Indexing ------------------------------------------------------------

  /// Add a document to the vector store.
  ///
  /// The document is chunked according to [chunkType], each chunk is
  /// embedded, and stored for later retrieval.
  Future<List<String>> addDocument({
    required String content,
    ChunkType chunkType = ChunkType.notes,
    String? source,
    Map<String, dynamic> metadata = const {},
  }) async {
    final chunks = _chunk(content, chunkType, source: source);
    final ids = <String>[];

    for (final chunk in chunks) {
      final id = _uuid.v4();
      final embedding = await _embed(chunk.content);
      final doc = VectorDocument(
        id: id,
        content: chunk.content,
        embedding: embedding,
        metadata: {...metadata, 'chunkType': chunkType.name},
        source: chunk.source,
        chunkIndex: chunk.index,
      );
      await _store.add(doc);
      ids.add(id);
    }

    _log.d('Indexed ${chunks.length} chunks from source: $source');
    return ids;
  }

  /// Index a [MemoryEntry] into the vector store.
  Future<String> addMemoryEntry(MemoryEntry entry) async {
    final embedding = await _embed(entry.content);
    final doc = VectorDocument(
      id: entry.id,
      content: entry.content,
      embedding: embedding,
      metadata: {
        'type': entry.type.name,
        'projectId': entry.projectId,
        'agentId': entry.agentId,
        'taskId': entry.taskId,
        'tags': entry.tags,
      },
      source: entry.fileRefs.isNotEmpty ? entry.fileRefs.first : null,
    );
    await _store.add(doc);
    _log.d('Indexed memory entry: ${entry.id}');
    return entry.id;
  }

  // ---- Search --------------------------------------------------------------

  /// Semantic search for the [topK] most relevant documents.
  Future<List<VectorSearchResult>> search(
    String query, {
    int topK = 10,
    double minScore = 0.1,
  }) async {
    final queryEmbedding = await _embed(query);
    return _store.search(queryEmbedding, topK: topK, minScore: minScore);
  }

  /// Get assembled context for a query — concatenated relevant chunks.
  Future<String> getContext(
    String query, {
    int topK = 5,
    int maxTokens = 4000,
  }) async {
    final results = await search(query, topK: topK);
    final buffer = StringBuffer();
    var estimatedTokens = 0;

    for (final result in results) {
      final chunkTokens = result.document.content.split(' ').length;
      if (estimatedTokens + chunkTokens > maxTokens) break;
      buffer.writeln('---');
      if (result.document.source != null) {
        buffer.writeln('Source: ${result.document.source}');
      }
      buffer.writeln('Score: ${result.score.toStringAsFixed(3)}');
      buffer.writeln(result.document.content);
      estimatedTokens += chunkTokens;
    }

    return buffer.toString();
  }

  /// Get context with citation tracking.
  Future<CitedContext> getCitedContext(
    String query, {
    int topK = 5,
    int maxTokens = 4000,
  }) async {
    final results = await search(query, topK: topK);
    final buffer = StringBuffer();
    final citations = <String>[];
    var estimatedTokens = 0;

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final chunkTokens = result.document.content.split(' ').length;
      if (estimatedTokens + chunkTokens > maxTokens) break;

      final citation = result.document.source ?? 'chunk-${result.document.id}';
      citations.add(citation);
      buffer.writeln('[${i + 1}] $citation');
      buffer.writeln(result.document.content);
      buffer.writeln();
      estimatedTokens += chunkTokens;
    }

    return CitedContext(context: buffer.toString(), citations: citations);
  }

  /// Compress context by removing low-relevance chunks.
  Future<String> compressContext(
    String query, {
    int maxTokens = 2000,
  }) async {
    return getContext(query, topK: 3, maxTokens: maxTokens);
  }

  /// Rank documents by relevance to [query].
  Future<List<VectorSearchResult>> rankByRelevance(
    String query, {
    int topK = 20,
  }) async {
    return search(query, topK: topK, minScore: 0.0);
  }

  // ---- Helpers -------------------------------------------------------------

  /// Generate an embedding for [text].
  Future<List<double>> _embed(String text) async {
    if (embedder != null) return embedder!(text);
    // Placeholder: deterministic hash-based embedding (128 dimensions).
    return _placeholderEmbedding(text);
  }

  /// Deterministic placeholder embedding based on character frequencies.
  List<double> _placeholderEmbedding(String text, {int dims = 128}) {
    final vec = List<double>.filled(dims, 0.0);
    for (var i = 0; i < text.length; i++) {
      vec[i % dims] += text.codeUnitAt(i).toDouble() / 256.0;
    }
    // Normalise.
    final norm = math.sqrt(vec.fold(0.0, (s, v) => s + v * v));
    if (norm > 0) {
      for (var i = 0; i < dims; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }

  /// Chunk content according to [type].
  List<TextChunk> _chunk(
    String content,
    ChunkType type, {
    String? source,
  }) {
    switch (type) {
      case ChunkType.code:
        return _chunkCode(content, source: source);
      case ChunkType.docs:
        return _chunkByHeadings(content, source: source);
      case ChunkType.notes:
        return _chunkByParagraph(content, source: source);
      case ChunkType.decisions:
        // Keep as a single chunk.
        return [TextChunk(content: content, index: 0, source: source)];
    }
  }

  List<TextChunk> _chunkCode(String content, {String? source}) {
    // Split on blank lines (simple heuristic for function boundaries).
    final blocks = content.split(RegExp(r'\n\n+'));
    return blocks
        .where((b) => b.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => TextChunk(content: e.value, index: e.key, source: source))
        .toList();
  }

  List<TextChunk> _chunkByHeadings(String content, {String? source}) {
    final sections = content.split(RegExp(r'\n(?=#+\s)'));
    return sections
        .where((s) => s.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => TextChunk(content: e.value, index: e.key, source: source))
        .toList();
  }

  List<TextChunk> _chunkByParagraph(String content, {String? source}) {
    final paragraphs = content.split(RegExp(r'\n\n+'));
    return paragraphs
        .where((p) => p.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => TextChunk(content: e.value, index: e.key, source: source))
        .toList();
  }
}
