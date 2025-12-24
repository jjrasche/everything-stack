# Media Tool Registry - User Behaviors

## Background
Given a running everything-stack app with media tools registered

---

## Feature: Extract YouTube Content Semantically

### Scenario: User downloads a video from YouTube
When the user says "download that programming tutorial video"
Then a download job is queued with:
  | Field    | Value          |
  | Format   | mp4            |
  | Quality  | 720p           |
  | Status   | queued         |
And the download is tracked for progress
And the user can check download status

### Scenario: Downloaded video is organized by channel
When a download completes for a video from "Computerphile"
Then the MediaItem is linked to Channel "Computerphile"
And the channel has new video count incremented
And the user's "watch later" list includes this video organized by channel

### Scenario: User converts format after download
When the user says "convert that tutorial to mp3"
Then the MediaItem is converted from mp4 to mp3
And a new MediaItem with mp3 format is created
And download progress shows conversion status

---

## Feature: Semantic Search Over Downloaded Library

### Scenario: User finds videos by meaning, not keywords
Given downloaded videos:
  | Title                          | Channel   |
  | "How embeddings work"          | ML Basics |
  | "Vector databases explained"   | DB Tech   |
  | "Semantic search in practice"  | AI Talks  |
When the user searches "how do I find similar vectors"
Then results include videos about embeddings and vectors
And results are ranked by semantic relevance (not keyword match)
And results are grouped by channel

### Scenario: Search returns nothing gracefully
When the user searches "underwater basket weaving tutorials"
And no videos match semantically
Then user sees "0 results" with suggestion to download from YouTube

---

## Feature: Channel Subscriptions and Watch Later

### Scenario: Subscribe to a channel for notifications
When the user subscribes to channel "ThePrimeagen"
Then the channel is marked as subscribed
And new videos from that channel get auto-downloaded (optional)
And user is notified when channel has new videos

### Scenario: Watch later organization
When the user marks 5 videos as "watch later"
And opens the app tomorrow
Then videos are grouped by channel
And progress is preserved (didn't delete after watching)
And user can resume from where they left off

---

## Feature: Watch Gestures for ML Training

### Scenario: System learns from watch behavior
When the user watches a video completely
Then the watch gesture is recorded:
  | Gesture        | Signal             |
  | Full watch     | High confidence    |
  | Skip to end    | Low confidence     |
  | Rewatch parts  | Medium + bookmark  |
  | Mark favorite  | High interest      |

When user watches 10 videos completely and skips 2
Then context manager learns this user prefers:
  | Topic           | Confidence |
  | Semantic search | 0.9        |
  | Databases       | 0.7        |

---

## Feature: Media Tool Integration with ContextManager

### Scenario: LLM routes "find videos" to media tools
When ContextManager receives event "show me semantic search tutorials"
Then ContextManager scores namespaces:
  | Namespace | Score  | Status  |
  | media     | 0.92   | PASS    |
  | task      | 0.3    | FAIL    |
  | timer     | 0.2    | FAIL    |
And routes to media namespace tools
And calls media.search with query "semantic search tutorials"

### Scenario: Tool composition for complex requests
When user says "download the algorithms course and organize it by topic"
Then ContextManager chains:
  1. media.download (get all course videos)
  2. media.organize (group by subtopic)
  3. media.search (test semantic understanding)
And result is organized course ready to watch

---

## Feature: Real YouTube DL Integration

### Scenario: Actual video download via YouTube DL
When media.download is called with YouTube URL
And the system has YouTube DL binary installed
Then:
  - YouTube DL starts downloading in background
  - Progress is streamed: % complete, current file, speed
  - On completion: MediaItem.blobId points to actual video file
  - Video is playable in app

### Scenario: Download with quality selection
When user requests "720p mp4" download
Then YouTube DL receives format="best[height=720]/best"
And downloaded file matches requested quality
And file size is recorded in MediaItem.fileSizeBytes
