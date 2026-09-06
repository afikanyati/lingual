import { useHeadphones } from "./hooks/useHeadphones";
import { HeadphoneStatus } from "./enums/headphones";
import { booleanSettings } from "./config/settings";
import type { RecordingPlaybackProgress } from "./interfaces/recording-playback";
import { HeadphoneReminder } from "./components/HeadphoneReminder";
import { headphoneReminder } from "./lib/headphone-reminder";
import type { HeadphoneReminderContext } from "./interfaces/headphones";
import {
  CommandCompletions,
  CommandGuide,
  SelectionSuggestions,
} from "./components/CommandDiscovery";
import {
  commandSuggestions,
  commonCommands,
  selectionSuggestions,
} from "./lib/command-suggestions";
import { BrowseClock, listPreviewSeconds } from "./lib/browse";
import { SelectionLoop } from "./lib/selection-loop";
import { NotificationQueue, PauseSuggestions } from "./lib/notifications";
import nativeHelp from "./lib/native-help.json";
import { openWelcome } from "./lib/welcome";
import { chooseLocalVoice, SpeakerPitch } from "./lib/voice";
import { pitchNote } from "./lib/pitch";
import type { PitchReading } from "./interfaces/pitch";
import {
  containsWords,
  textFragments,
  punctuationPresentation,
  sourceSelection,
  displaySelection,
} from "./lib/punctuation";
import { Button } from "./components/Button";
import { useEffect, useRef, useState } from "react";
import {
  AudioLines,
  ArrowDownToLine,
  ArrowUpFromLine,
  BookOpen,
  ChevronDown,
  CircleHelp,
  Copy,
  FileText,
  Headphones,
  Mic,
  MoreHorizontal,
  Pause,
  Play,
  Plus,
  Redo2,
  Search,
  Settings2,
  ShieldCheck,
  Sparkles,
  Square,
  Trash2,
  Undo2,
  X,
  Scissors,
  ClipboardPaste,
  LoaderCircle,
  Volume2,
} from "lucide-react";
import type { AudioClip, Entry } from "./interfaces/entry";
import { SpeechStatus } from "./enums/speech";
import { createEntry, entryTitle, wordCount } from "./lib/editor";
import {
  decodeAudio,
  downloadBlob,
  encodeWav,
  formatTime,
  hasSpeechEnergy,
} from "./lib/audio";
import * as storage from "./lib/storage";
import { SpeechClient } from "./speech/client";
import { LiveSpeechClient } from "./speech/live";
import type { PendingSpeech, ProvisionalSpeech } from "./interfaces/speech";
import { MicrophoneCapture } from "./speech/capture";
import { Command } from "./enums/command";
import {
  commandCatalog,
  defaultPreferences,
  executeCommand,
  parseCommand,
} from "./lib/commands";
import {
  insertPassage,
  copyPassage,
  playbackSlices,
  transcriptPassage,
  selectionAudioTime,
} from "./lib/timeline";
import { hasCompleteAudio } from "./lib/audio-integrity";
import { TimelinePlayer, renderTimeline } from "./lib/playback";
import type {
  CommandContext,
  CommandEffect,
  BrowseState,
  SelectionUpdate,
  Preferences,
  RecordingPosition,
} from "./interfaces/workspace";
import type { Passage } from "./interfaces/timeline";
import type { TextSelection } from "./interfaces/entry";
import type { EchoCursor } from "./interfaces/text";
import {
  annotateProsody,
  commitNotifications,
  presentationFragments,
  entryPresentation,
  displayWord,
  displayGap,
  presentedText,
  echoFragments,
  echoSourceRange,
} from "./lib/prosody";
import { playFeedback } from "./lib/feedback";
import { restoreSession } from "./lib/session";
import { useLibraryDrawer } from "./hooks/useLibraryDrawer";
import { exportBackup, importBackup } from "./lib/backup";
import "./styles.css";

// Examples come from the native catalog so guidance cannot advertise invented actions.
const commandExamples = [
  Command.SELECT_PARAGRAPH,
  Command.UNDO_CHANGE,
  Command.SELECT_WORD,
  Command.ECHO_ENTRY,
  Command.COPY_SELECTION,
  Command.DELETE_SELECTION,
  Command.PASTE_CLIPBOARD,
  Command.STOP_ENTRY,
].map((id) => commandCatalog.find((command) => command.id === id)!.label);
const errorMessage = (error: unknown) =>
  error instanceof Error ? error.message : String(error);

export default function App() {
  const [entries, setEntries] = useState<Entry[]>([]);
  const entriesRef = useRef<Entry[]>([]);
  const [activeId, setActiveId] = useState("");
  const activeIdRef = useRef("");
  const [loaded, setLoaded] = useState(false);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState(SpeechStatus.Idle);
  const statusRef = useRef(SpeechStatus.Idle);
  const [progress, setProgress] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const speakerPitch = useRef<SpeakerPitch | undefined>(undefined);
  if (!speakerPitch.current) {
    let savedPitch: number | undefined;
    try {
      savedPitch = Number(localStorage.getItem("lingual-speaker-pitch"));
    } catch {
      /* Storage can be unavailable. */
    }
    speakerPitch.current = new SpeakerPitch(savedPitch);
  }
  const [livePitch, setLivePitch] = useState<PitchReading>();
  const [playbackPitch, setPlaybackPitch] = useState<number>();
  const [pending, setPending] = useState(0);
  const liveEngine = useRef(new LiveSpeechClient());
  const [provisional, setProvisional] = useState<ProvisionalSpeech[]>([]);
  const [commandPreview, setCommandPreview] = useState<ProvisionalSpeech>();
  const [recognizedAction, setRecognizedAction] = useState("");
  const [message, setMessage] = useState("");
  const [requestedHeadphoneFeature, setRequestedHeadphoneFeature] =
    useState<HeadphoneReminderContext["requestedFeature"]>();
  const [notice, setNotice] = useState("");
  const notices = useRef(new NotificationQueue(setNotice));
  const pauseSuggestions = useRef<PauseSuggestions | undefined>(undefined);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [welcomeLoading, setWelcomeLoading] = useState(false);
  const [commands, setCommands] = useState(() => {
    try {
      return localStorage.getItem("lingual-voice-actions") !== "false";
    } catch {
      return true;
    }
  });
  const commandsRef = useRef(commands);
  const [dialog, setDialog] = useState<
    "help" | "settings" | "delete" | "export" | null
  >(null);
  const [clips, setClips] = useState<AudioClip[]>([]);
  const [showRecordings, setShowRecordings] = useState(false);
  const [echoing, setEchoing] = useState(false);
  const [echoPaused, setEchoPaused] = useState(false);
  const interactionContext = useRef<
    Pick<CommandContext, "playback" | "dialog">
  >({});
  const echoGeneration = useRef(0);
  const playbackGeneration = useRef(0);
  const auditionTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const [localVoices, setLocalVoices] = useState<SpeechSynthesisVoice[]>([]);
  const echoCursor = useRef<EchoCursor | undefined>(undefined);
  const [playingClip, setPlayingClip] = useState("");
  const [clipProgress, setClipProgress] = useState<RecordingPlaybackProgress>();
  const [menu, setMenu] = useState(false);
  const { compactLayout, mobileLibrary, setMobileLibrary } = useLibraryDrawer(
    Boolean(dialog),
  );
  const [preferences, setPreferences] = useState<Preferences>(() => {
    try {
      const stored = JSON.parse(
        localStorage.getItem("lingual-preferences") || "{}",
      );
      // Remove the retired manual flag; only live output detection controls these features.
      if (Object.hasOwn(stored, "headphones")) {
        delete stored.headphones;
        localStorage.setItem("lingual-preferences", JSON.stringify(stored));
      }
      return { ...defaultPreferences, ...stored };
    } catch {
      return { ...defaultPreferences };
    }
  });
  const preferencesRef = useRef(preferences);
  const headphones = useHeadphones();
  const headphonesConnected = headphones.status === HeadphoneStatus.Headphones;
  const echoRequiresHeadphones = useRef(false);
  const audioClipboard = useRef<Passage>({ text: "", spans: [] });
  const [replacement, setReplacement] = useState<SelectionUpdate>();
  const replacementRef = useRef<SelectionUpdate | undefined>(undefined);
  const [browse, setBrowse] = useState<BrowseState>();
  const browseRef = useRef<BrowseState | undefined>(undefined);
  const browseClock = useRef(new BrowseClock());
  const selectionLoop = useRef(new SelectionLoop());
  const selectionOwnsAudio = useRef(false);
  const resumeSelectedDictation = useRef<string | undefined>(undefined);
  const suspendedBrowse = useRef<BrowseState | undefined>(undefined);
  const suspendedListening = useRef<"dictation" | "commands" | undefined>(
    undefined,
  );
  const browseTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const [playbackRange, setPlaybackRange] = useState<TextSelection>();
  const [playbackPosition, setPlaybackPosition] = useState(0);
  const [timelinePlaying, setTimelinePlaying] = useState(false);
  interactionContext.current = {
    dialog,
    playback:
      echoing || echoPaused
        ? "echo"
        : playbackRange || timelinePlaying
          ? "audio"
          : undefined,
  };
  const [showTimeline, setShowTimeline] = useState(false);
  const [commandSearch, setCommandSearch] = useState("");
  const effectRef = useRef<(effect: CommandEffect) => Promise<void>>(
    async () => {},
  );
  const timelinePlayer = useRef<TimelinePlayer | undefined>(undefined);
  const browseRunner = useRef<() => Promise<void>>(async () => {});
  const listenMode = useRef<"dictation" | "commands">("dictation");
  const [commandListening, setCommandListening] = useState(false);
  const [heardSpeech, setHeardSpeech] = useState("");
  const exportRange = useRef<TextSelection | undefined>(undefined);
  const textarea = useRef<HTMLTextAreaElement>(null);
  const backupUpload = useRef<HTMLInputElement>(null);
  const engine = useRef(new SpeechClient());
  const modelReady = useRef(false);
  const capture = useRef<MicrophoneCapture | undefined>(undefined);
  const queue = useRef(Promise.resolve());
  const writes = useRef(Promise.resolve());
  const saveVersion = useRef(0);
  const pendingRef = useRef(0);
  const stopping = useRef<Promise<void> | undefined>(undefined);
  const stopRef = useRef<() => Promise<void>>(async () => {});
  const audioPlayer = useRef<HTMLAudioElement | undefined>(undefined);
  const audioURL = useRef("");
  const entry = entries.find((item) => item.id === activeId);
  const liveWords = provisional.filter(
    (item) => item.entryId === activeId && item.text,
  );
  const provisionalNode = liveWords.length ? (
    <span
      key="provisional"
      className="provisional-speech"
      aria-label="Uncommitted speech"
      aria-live="polite"
    >
      {liveWords.map((item) => (
        <span key={item.id}>{item.text} </span>
      ))}
    </span>
  ) : null;
  const recording = status === SpeechStatus.Listening;
  const headphoneMessage = headphoneReminder({
    preferences,
    headphoneStatus: headphones.status,
    listening: recording && !commandListening,
    selection: Boolean(
      entry && entry.selection.end > entry.selection.start && !replacement,
    ),
    browsing: Boolean(browse),
    handsFreePlayback: commands && Boolean(timelinePlaying || echoing),
    settingsOpen: dialog === "settings",
    requestedFeature: requestedHeadphoneFeature,
  });
  const discoveryContext = entry
    ? {
        ...getCommandContext(entry),
        listening: recording,
      }
    : undefined;
  const suggestions =
    commands &&
    recording &&
    !dialog &&
    commandPreview?.entryId === activeId &&
    discoveryContext
      ? commandSuggestions(commandPreview.text, discoveryContext)
      : [];
  const busy =
    exporting ||
    welcomeLoading ||
    recording ||
    status === SpeechStatus.Starting ||
    status === SpeechStatus.Finishing ||
    pending > 0;

  const changeStatus = (next: SpeechStatus) => {
    statusRef.current = next;
    setStatus(next);
  };
  const showError = (cause: unknown) => {
    setError(errorMessage(cause));
    setMessage("");
    if (preferencesRef.current.voiceFeedback)
      playFeedback("error", preferencesRef.current.volume);
  };

  /** Update the ref synchronously so a speech result cannot overwrite a newer keyboard edit. */
  function updateEntry(
    id: string,
    transform: (current: Entry) => Entry,
    persist = true,
  ) {
    let updated: Entry | undefined;
    const next = entriesRef.current.map((current) => {
      if (current.id !== id) return current;
      updated = transform(current);
      return updated;
    });
    entriesRef.current = next;
    setEntries(next);
    if (!updated || !persist) return;
    const snapshot = updated;
    const version = ++saveVersion.current;
    setSaved(false);
    writes.current = writes.current
      .then(() => storage.saveEntry(snapshot))
      .then(() => {
        if (saveVersion.current === version) setSaved(true);
      })
      .catch((cause) => {
        setSaved(false);
        showError(
          `Could not save this entry: ${errorMessage(cause)}. Export your text before closing.`,
        );
      });
  }
  function selectEntry(id: string) {
    if (busy) return;
    stopPlayback();
    browseRef.current = undefined;
    setBrowse(undefined);
    setActiveId(id);
    activeIdRef.current = id;
    setMobileLibrary(false);
    setShowRecordings(false);
  }
  function newEntry() {
    if (busy) return;
    const created = createEntry();
    entriesRef.current = [created, ...entriesRef.current];
    setEntries(entriesRef.current);
    selectEntry(created.id);
    updateEntry(created.id, (value) => value);
    setTimeout(() => textarea.current?.focus(), 0);
  }
  function syncSelection(updated: Entry) {
    requestAnimationFrame(() => {
      if (activeIdRef.current !== updated.id) return;
      textarea.current?.focus();
      const visible = displaySelection(
        entryPresentation(updated, preferencesRef.current),
        updated.selection,
      );
      textarea.current?.setSelectionRange(visible.start, visible.end);
    });
  }
  function stopPlayback(preserveBrowse = false) {
    clearTimeout(auditionTimer.current);
    ++playbackGeneration.current;
    ++echoGeneration.current;
    setEchoPaused(false);
    timelinePlayer.current?.stop();
    setTimelinePlaying(false);
    setPlaybackPitch(undefined);
    setPlaybackRange(undefined);
    if (!preserveBrowse) {
      selectionLoop.current.stop();
      selectionOwnsAudio.current = false;
      clearTimeout(browseTimer.current);
      browseClock.current.stop();
    }
    speechSynthesis.cancel();
    setEchoing(false);
    releaseOriginalRecording();
    setPlayingClip("");
    setClipProgress(undefined);
  }
  /** Native idle taps audition the touched audio briefly, then leave playback ready at that word. */
  async function auditionWord(start: number) {
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current || capture.current || headphones.connected.current) return;
    const range = { start, end: current.text.length };
    const duration =
      playbackSlices(
        current,
        range,
        preferencesRef.current.omitSilences,
      ).reduce(
        (sum, slice) => sum + (slice.end - slice.start) / slice.rate,
        0,
      ) / preferencesRef.current.playbackRate;
    if (!duration) return;
    await playPassage(range);
    const generation = playbackGeneration.current;
    // Very short final words must pause before they finish, rather than lose their prepared position.
    auditionTimer.current = setTimeout(
      () => {
        if (generation !== playbackGeneration.current) return;
        timelinePlayer.current?.pause();
        setTimelinePlaying(false);
      },
      Math.min(200, duration * 500),
    );
  }
  /** Selection audio and explicit playback share one player, so only the current owner may repeat it. */
  function repeatSelection(range: TextSelection) {
    selectionOwnsAudio.current = true;
    selectionLoop.current.start(
      () =>
        new Promise<void>((resolve, reject) => {
          void playPassage(range, undefined, resolve, true).catch(reject);
        }),
      showError,
    );
  }

  /** Return to the interrupted review or microphone mode only while its entry and scope still exist. */
  async function resumeInterruptedReview() {
    const previous = suspendedBrowse.current;
    suspendedBrowse.current = undefined;
    if (previous && browseRef.current === previous) {
      const resumed = { ...previous, paused: false };
      browseRef.current = resumed;
      setBrowse(resumed);
      await runBrowseStep();
    }
    const mode = suspendedListening.current;
    suspendedListening.current = undefined;
    if (mode && !document.hidden) {
      const desired = browseRef.current ? "commands" : mode;
      if (capture.current && listenMode.current !== desired)
        await stopRef.current();
      if (!capture.current) await startListening(desired);
    }
  }
  /** Paused loudspeaker playback can hear Resume; restarting output releases that command microphone first. */
  async function listenDuringPlaybackPause() {
    if (suspendedListening.current && commandsRef.current && !capture.current)
      await startListening("commands");
  }
  async function suspendPlaybackListening() {
    if (!capture.current || headphones.connected.current) return;
    suspendedListening.current ??= listenMode.current;
    await stopRef.current();
  }
  function echo() {
    if (echoing) {
      dispatchCommand(Command.STOP_ECHO);
      return;
    }
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current?.text.trim()) return;
    dispatchCommand(
      current.selection.end > current.selection.start
        ? Command.ECHO_SELECTION
        : Command.ECHO_ENTRY,
    );
  }
  /** Detach callbacks before releasing audio so late media events cannot affect another recording. */
  function releaseOriginalRecording() {
    const audio = audioPlayer.current;
    audioPlayer.current = undefined;
    if (audio) {
      audio.onended = null;
      audio.onerror = null;
      audio.ontimeupdate = null;
      audio.onloadedmetadata = null;
      audio.ondurationchange = null;
      audio.onpause = null;
      audio.onplaying = null;
      audio.pause();
    }
    if (audioURL.current) URL.revokeObjectURL(audioURL.current);
    audioURL.current = "";
  }

  /** Play or resume an original recording using the media clock, independently of edited-entry playback. */
  function playClip(clip: AudioClip) {
    if (recording) return;
    if (playingClip === clip.id && audioPlayer.current) {
      audioPlayer.current.pause();
      setPlayingClip("");
      return;
    }
    const play = (audio: HTMLAudioElement) => {
      setPlayingClip(clip.id);
      void audio.play().catch((cause) => {
        if (audioPlayer.current !== audio) return;
        stopPlayback();
        showError(cause);
      });
    };
    if (clipProgress?.id === clip.id && audioPlayer.current) {
      play(audioPlayer.current);
      return;
    }
    stopPlayback();
    audioURL.current = URL.createObjectURL(clip.audio);
    const audio = new Audio(audioURL.current);
    audioPlayer.current = audio;
    audio.playbackRate = preferencesRef.current.playbackRate;
    audio.volume = preferencesRef.current.volume;
    const duration = () =>
      Number.isFinite(audio.duration) && audio.duration > 0
        ? audio.duration
        : Math.max(0, Number.isFinite(clip.duration) ? clip.duration : 0);
    const updateProgress = () => {
      if (audioPlayer.current !== audio) return;
      const total = duration();
      const position = Number.isFinite(audio.currentTime)
        ? Math.max(0, Math.min(total, audio.currentTime))
        : 0;
      setClipProgress({ id: clip.id, position, duration: total });
    };
    audio.ontimeupdate = updateProgress;
    audio.onloadedmetadata = updateProgress;
    audio.ondurationchange = updateProgress;
    audio.onplaying = () => {
      if (audioPlayer.current === audio) setPlayingClip(clip.id);
    };
    audio.onpause = () => {
      if (audioPlayer.current === audio) {
        updateProgress();
        setPlayingClip("");
      }
    };
    audio.onended = () => {
      if (audioPlayer.current !== audio) return;
      const total = duration();
      stopPlayback();
      setClipProgress({ id: clip.id, position: total, duration: total });
    };
    audio.onerror = () => {
      if (audioPlayer.current !== audio) return;
      stopPlayback();
      showError(
        "This recording could not be played. Try downloading the WAV file.",
      );
    };
    updateProgress();
    play(audio);
  }
  function exportText() {
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (current)
      downloadBlob(
        new Blob(
          [
            presentedText(current, preferencesRef.current, {
              start: 0,
              end: current.text.length,
            }),
          ],
          { type: "text/plain;charset=utf-8" },
        ),
        `${entryTitle(current).replace(/[^\w -]/g, "") || "Lingual"}.txt`,
      );
  }
  function getCommandContext(current: Entry): CommandContext {
    return {
      ...interactionContext.current,
      entry: current,
      preferences: preferencesRef.current,
      clipboard: audioClipboard.current,
      replacement: replacementRef.current,
      browse: browseRef.current,
    };
  }
  function updatePreferences(next: Preferences) {
    const previous = preferencesRef.current;
    if (next.passiveEcho && !previous.passiveEcho)
      setRequestedHeadphoneFeature("passiveEcho");
    else if (next.voiceFeedback && !previous.voiceFeedback)
      setRequestedHeadphoneFeature("voiceFeedback");
    preferencesRef.current = next;
    setPreferences(next);
    if (!next.punctuationSuggestions) pauseSuggestions.current?.stop();
    timelinePlayer.current?.setVolume(next.volume);
    if (audioPlayer.current) {
      audioPlayer.current.volume = next.volume;
      audioPlayer.current.playbackRate = next.playbackRate;
    }
    if (previous.playbackRate !== next.playbackRate)
      timelinePlayer.current?.changeRate(
        next.playbackRate / previous.playbackRate,
      );
    if (
      (previous.echoRate !== next.echoRate ||
        previous.volume !== next.volume) &&
      speechSynthesis.speaking &&
      echoCursor.current
    ) {
      const cursor = echoCursor.current;
      speakRange({ start: cursor.position, end: cursor.range.end });
    }
    try {
      localStorage.setItem("lingual-preferences", JSON.stringify(next));
    } catch (cause) {
      showError(cause);
    }
  }
  /** Spoken notices share the local synthesizer queue with passive echo, and require headphones. */
  function speakNotice(text: string) {
    if (preferencesRef.current.voiceFeedback && headphones.connected.current) {
      const voice = chooseLocalVoice(
        speechSynthesis.getVoices(),
        preferencesRef.current.voiceURI,
        speakerPitch.current?.value,
        navigator.language,
      );
      if (voice) {
        const spoken = new SpeechSynthesisUtterance(text);
        spoken.voice = voice;
        spoken.volume = preferencesRef.current.volume;
        spoken.rate = preferencesRef.current.echoRate;
        echoRequiresHeadphones.current = true;
        speechSynthesis.speak(spoken);
      }
    }
  }
  function dispatchCommand(command: Command, target = activeIdRef.current) {
    const current = entriesRef.current.find((item) => item.id === target);
    if (!current) return;
    const outcome = executeCommand(command, getCommandContext(current));
    if (
      command === Command.ACTIVATE_PASSIVE_ECHO &&
      outcome.preferences.passiveEcho
    )
      setRequestedHeadphoneFeature("passiveEcho");
    audioClipboard.current = outcome.clipboard;
    replacementRef.current = outcome.replacement;
    setReplacement(outcome.replacement);
    browseRef.current = outcome.browse;
    setBrowse(outcome.browse);
    updatePreferences(outcome.preferences);
    updateEntry(target, () => outcome.entry);
    if (
      outcome.entry.selection.start !== current.selection.start ||
      outcome.entry.selection.end !== current.selection.end
    )
      syncSelection(outcome.entry);
    notices.current.push(outcome.message, 2200);
    if (preferencesRef.current.voiceFeedback)
      playFeedback(
        outcome.message.startsWith("Select some")
          ? "voice-command-deny"
          : "voice-command-accept",
        preferencesRef.current.volume,
      );
    if (outcome.effect)
      setTimeout(
        () =>
          void effectRef
            .current(outcome.effect!)
            .then(() => speakNotice(outcome.message))
            .catch(showError),
        0,
      );
    else speakNotice(outcome.message);
  }
  async function playPassage(
    range: TextSelection,
    passage?: Passage,
    ended?: () => void,
    preserveBrowse = false,
  ) {
    stopPlayback(preserveBrowse);
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current) return;
    const source = passage
      ? { ...current, text: passage.text, spans: passage.spans }
      : current;
    const selectedRange = passage
      ? { start: 0, end: passage.text.length }
      : range;
    const slices = playbackSlices(
      source,
      selectedRange,
      preferencesRef.current.omitSilences,
    ).map((slice) => ({
      ...slice,
      rate: slice.rate * preferencesRef.current.playbackRate,
    }));
    if (
      !slices.length ||
      !hasCompleteAudio(copyPassage(source, selectedRange))
    ) {
      setMessage(
        "There is no complete original recording for this passage. Speak a replacement or retry its saved audio.",
      );
      ended?.();
      return;
    }
    // A newer Play or Stop can supersede this request while its context is closing.
    const generation = playbackGeneration.current;
    const previousPlayer = timelinePlayer.current;
    timelinePlayer.current = undefined;
    await previousPlayer?.dispose();
    if (generation !== playbackGeneration.current) return;
    timelinePlayer.current = new TimelinePlayer({
      onPosition: (start, end, seconds) => {
        setPlaybackRange({ start, end });
        setPlaybackPosition(seconds);
        setPlaybackPitch(
          source.spans.find((span) => span.start < end && span.end > start)
            ?.pitch,
        );
      },
      onEnd: () => {
        setTimelinePlaying(false);
        setPlaybackPitch(undefined);
        setPlaybackRange(undefined);
        ended?.();
      },
    });
    setShowTimeline(true);
    setTimelinePlaying(true);
    try {
      await timelinePlayer.current.load(
        slices,
        storage.loadClip,
        preferencesRef.current.volume,
      );
    } catch (cause) {
      setTimelinePlaying(false);
      ended?.();
      throw cause;
    }
  }
  function speakRange(
    range: TextSelection,
    ended?: () => void,
    queueAfterCurrent = false,
  ) {
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    const fragments = current
      ? echoFragments(current, preferencesRef.current, range)
      : [];
    const phrase = fragments.map((fragment) => fragment.text).join("");
    if (!phrase.trim()) {
      ended?.();
      return;
    }
    if (!queueAfterCurrent) {
      ++echoGeneration.current;
      speechSynthesis.cancel();
    }
    const generation = echoGeneration.current;
    echoRequiresHeadphones.current =
      queueAfterCurrent || Boolean(browseRef.current);
    setEchoPaused(false);
    const voice = chooseLocalVoice(
      speechSynthesis.getVoices(),
      preferencesRef.current.voiceURI,
      speakerPitch.current?.value,
      navigator.language,
    );
    if (!voice) {
      setMessage(
        "Download an English system speech voice to enable private read-back on this device.",
      );
      ended?.();
      return;
    }
    const utterance = new SpeechSynthesisUtterance(phrase);
    utterance.voice = voice;
    echoCursor.current = { range, position: range.start };
    utterance.rate = preferencesRef.current.echoRate;
    utterance.volume = preferencesRef.current.volume;
    utterance.lang = "en-US";
    utterance.onboundary = (event) => {
      if (generation !== echoGeneration.current) return;
      const source = echoSourceRange(fragments, event.charIndex);
      if (!source) return;
      if (echoCursor.current) echoCursor.current.position = source.start;
      if (event.name === "word") setPlaybackRange(source);
    };
    utterance.onend = () => {
      if (generation !== echoGeneration.current) return;
      setEchoPaused(false);
      setEchoing(false);
      setPlaybackRange(undefined);
      ended?.();
    };
    utterance.onerror = () => {
      if (generation !== echoGeneration.current) return;
      setEchoPaused(false);
      setEchoing(false);
      setPlaybackRange(undefined);
      ended?.();
    };
    speechSynthesis.speak(utterance);
    setEchoing(true);
  }
  async function exportPassage(format: "audio" | "text", range: TextSelection) {
    setExporting(true);
    try {
      const current = entriesRef.current.find(
        (item) => item.id === activeIdRef.current,
      );
      if (!current) return;
      const filename = entryTitle(current).replace(/[^\w -]/g, "") || "Lingual";
      if (format === "text") {
        downloadBlob(
          new Blob([presentedText(current, preferencesRef.current, range)], {
            type: "text/plain;charset=utf-8",
          }),
          `${filename}.txt`,
        );
        return;
      }
      const slices = playbackSlices(
        current,
        range,
        preferencesRef.current.omitSilences,
      ).map((slice) => ({
        ...slice,
        rate: slice.rate * preferencesRef.current.playbackRate,
        gain: slice.gain * preferencesRef.current.volume,
      }));
      if (!slices.length || !hasCompleteAudio(copyPassage(current, range))) {
        setMessage(
          "This passage has no complete original recording to export. Speak a replacement or retry its saved audio.",
        );
        return;
      }
      downloadBlob(
        await renderTimeline(slices, storage.loadClip),
        `${filename}.wav`,
      );
    } finally {
      setExporting(false);
    }
  }
  async function confirmDelete() {
    await stopRef.current();
    await writes.current;
    const id = activeIdRef.current;
    if (preferencesRef.current.voiceFeedback)
      playFeedback("delete", preferencesRef.current.volume);
    await storage.deleteEntry(
      id,
      audioClipboard.current.spans.map((span) => span.clipId),
    );
    const remaining = entriesRef.current.filter((item) => item.id !== id);
    const next = remaining[0] ?? createEntry();
    entriesRef.current = remaining.length ? remaining : [next];
    setEntries(entriesRef.current);
    activeIdRef.current = next.id;
    setActiveId(next.id);
    setDialog(null);
    if (!remaining.length) updateEntry(next.id, (value) => value);
  }
  async function runBrowseStep() {
    clearTimeout(browseTimer.current);
    const state = browseRef.current;
    if (!state || state.paused) return;
    let range = state.ranges[state.index];
    if (state.scope === "list") {
      const item = entriesRef.current[state.index];
      if (!item) {
        dispatchCommand(Command.EXIT_WALK);
        return;
      }
      activeIdRef.current = item.id;
      setActiveId(item.id);
      range = { start: 0, end: item.text.length };
    }
    if (!range) {
      dispatchCommand(Command.PAUSE_RUN);
      return;
    }
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current) return;
    updateEntry(current.id, (value) => ({ ...value, selection: range }), false);
    setShowTimeline(true);
    stopPlayback();
    const next = () => {
      if (browseRef.current !== state || state.paused) return;
      if (state.mode === "run") {
        const atEnd =
          state.index + 1 >=
          (state.scope === "list"
            ? entriesRef.current.length
            : state.ranges.length);
        if (atEnd && state.scope === "list") {
          dispatchCommand(Command.EXIT_WALK);
          return;
        }
        const advanced: BrowseState = atEnd
          ? { ...state, mode: "walk" }
          : { ...state, index: state.index + 1 };
        browseRef.current = advanced;
        setBrowse(advanced);
      }
      void browseRunner.current().catch(showError);
    };
    if (state.scope === "list") {
      const duration = playbackSlices(
        current,
        range,
        preferencesRef.current.omitSilences,
      ).reduce((sum, slice) => sum + (slice.end - slice.start) / slice.rate, 0);
      if (headphones.connected.current && duration > 0)
        await playPassage(range, undefined, undefined, true);
      browseTimer.current = setTimeout(
        next,
        1000 *
          listPreviewSeconds(
            state.mode,
            duration,
            preferencesRef.current.playbackRate,
          ),
      );
      return;
    }
    const wordDuration = playbackSlices(current, range, true).reduce(
      (sum, slice) => sum + (slice.end - slice.start) / slice.rate,
      0,
    );
    browseClock.current.start({
      mode: state.mode,
      headphonesConnected: headphones.connected.current,
      rate: preferencesRef.current.playbackRate,
      duration: wordDuration,
      play: () =>
        new Promise<void>((resolve, reject) => {
          void playPassage(range, undefined, resolve, true).catch(reject);
        }),
      echo: () => speakRange(range),
      next,
      onError: showError,
    });
  }

  browseRunner.current = runBrowseStep;
  async function performEffect(effect: CommandEffect) {
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current) return;
    const range = effect.range ?? { start: 0, end: current.text.length };
    switch (effect.kind) {
      case "listen":
        if (capture.current && listenMode.current === "commands")
          await stopRef.current();
        await startListening("dictation");
        break;
      case "stop-listening":
        resumeSelectedDictation.current = undefined;
        suspendedListening.current = undefined;
        await finishEntry();
        break;
      case "new-entry": {
        await stopRef.current();
        const created = createEntry();
        entriesRef.current = [created, ...entriesRef.current];
        setEntries(entriesRef.current);
        activeIdRef.current = created.id;
        setActiveId(created.id);
        updateEntry(created.id, (value) => value);
        if (effect.startRecording) await startListening("dictation");
        break;
      }
      case "delete-entry":
        await stopRef.current();
        setDialog("delete");
        if (commandsRef.current && modelReady.current)
          await startListening("commands");
        break;
      case "library":
        setMobileLibrary(true);
        break;
      case "open-entry":
        stopPlayback();
        setMobileLibrary(false);
        textarea.current?.focus();
        break;
      case "help":
        setDialog("help");
        break;
      case "close-dialog":
        setDialog(null);
        break;
      case "confirm-dialog":
        if (dialog === "delete") await confirmDelete();
        else if (replacementRef.current)
          dispatchCommand(Command.ACCEPT_SELECTION_UPDATE);
        else setDialog(null);
        break;
      case "permissions":
        await startListening("commands");
        break;
      case "export":
        if (effect.format === "choose") {
          exportRange.current = range;
          setDialog("export");
        } else await exportPassage(effect.format ?? "text", range);
        break;
      case "play":
      case "echo":
      case "browse": {
        // Native playback announces itself only outside dictation, selection and browsing.
        if (
          effect.kind !== "browse" &&
          !capture.current &&
          !browseRef.current &&
          current.selection.start === current.selection.end &&
          preferencesRef.current.voiceFeedback
        )
          playFeedback("play", preferencesRef.current.volume);
        // Loudspeaker output must not be recognized as a new entry or as a voice action.
        if (
          capture.current &&
          (listenMode.current === "dictation" || !headphones.connected.current)
        ) {
          suspendedListening.current = listenMode.current;
          await stopRef.current();
        }
        let playbackScope = range;
        if (
          effect.kind !== "browse" &&
          browseRef.current &&
          !browseRef.current.paused
        ) {
          const previous = { ...browseRef.current, paused: true };
          suspendedBrowse.current = previous;
          browseRef.current = previous;
          setBrowse(previous);
          // A full-entry command inside a word walk previews that walk's complete scope.
          if (
            !effect.passage &&
            previous.scope !== "list" &&
            range.start === 0 &&
            range.end === current.text.length
          )
            playbackScope = {
              start: previous.ranges[0].start,
              end: previous.ranges.at(-1)!.end,
            };
        }
        const finished = () => void resumeInterruptedReview().catch(showError);
        if (effect.kind === "play")
          await playPassage(playbackScope, effect.passage, finished);
        if (effect.kind === "echo") {
          stopPlayback();
          speakRange(playbackScope, finished);
        }
        if (effect.kind === "browse") await runBrowseStep();
        if (
          commandsRef.current &&
          modelReady.current &&
          !capture.current &&
          (headphones.connected.current || effect.kind === "browse")
        )
          await startListening("commands");
        break;
      }
      case "pause-playback":
        timelinePlayer.current?.pause();
        audioPlayer.current?.pause();
        setTimelinePlaying(false);
        await listenDuringPlaybackPause();
        break;
      case "resume-playback":
        await suspendPlaybackListening();
        timelinePlayer.current?.resume();
        if (audioPlayer.current) await audioPlayer.current.play();
        setTimelinePlaying(true);
        break;
      case "stop-playback":
        stopPlayback();
        await resumeInterruptedReview();
        break;
      case "pause-echo":
        speechSynthesis.pause();
        setEchoPaused(true);
        setEchoing(false);
        await listenDuringPlaybackPause();
        break;
      case "resume-echo":
        await suspendPlaybackListening();
        speechSynthesis.resume();
        setEchoPaused(false);
        setEchoing(true);
        break;
      case "stop-echo":
        ++echoGeneration.current;
        speechSynthesis.cancel();
        setEchoPaused(false);
        setEchoing(false);
        setPlaybackRange(undefined);
        await resumeInterruptedReview();
        break;
      case "seek":
        timelinePlayer.current?.seek(effect.offset ?? 0);
        if (audioPlayer.current)
          audioPlayer.current.currentTime = Math.max(
            0,
            audioPlayer.current.currentTime + (effect.offset ?? 0),
          );
        break;
      default: {
        const exhaustive: never = effect.kind;
        throw new Error(`Unhandled effect: ${exhaustive}`);
      }
    }
  }
  effectRef.current = performEffect;

  /** Persist audio first, then serialize inference. Every result stays bound to its originating entry. */
  function enqueue(
    audio: Float32Array,
    targetId: string,
    retry?: AudioClip,
    recording?: RecordingPosition,
    live?: PendingSpeech,
  ) {
    // Listening-only audio is ephemeral. Do not create a clip, link it to an
    // entry, or send ordinary speech through the slower dictation model.
    if (!retry && listenMode.current === "commands") {
      const microphone = capture.current;
      queue.current = queue.current
        .then(async () => {
          const result = await live?.result;
          if (result?.command && microphone && capture.current === microphone)
            dispatchCommand(result.command, targetId);
        })
        .catch((cause) => {
          showError(cause);
          void stopRef.current();
        });
      return;
    }
    const clip: AudioClip = retry ?? {
      recordingId: recording?.id,
      recordingOffset: recording?.offset,
      id: crypto.randomUUID(),
      entryId: targetId,
      audio: encodeWav(audio),
      duration: audio.length / 16000,
      createdAt: new Date().toISOString(),
      transcript: "",
      transcribed: false,
    };
    const capturedMode = listenMode.current;
    const capturedCommands = commandsRef.current;
    // Start persistence immediately, even when earlier transcription is still running.
    const durable = storage.saveClip(clip);
    durable.catch((cause) => {
      showError(`Could not save microphone audio: ${errorMessage(cause)}`);
      void stopRef.current();
    });
    pendingRef.current += 1;
    setPending(pendingRef.current);
    if (pendingRef.current >= 8) {
      setMessage(
        "Transcription is catching up. Listening is paused to keep your recordings safe.",
      );
      void stopRef.current();
    }
    queue.current = queue.current
      .then(async () => {
        await durable;
        if (!retry)
          updateEntry(targetId, (current) => ({
            ...current,
            clipIds: [...current.clipIds, clip.id],
          }));
        if (activeIdRef.current === targetId)
          setClips(await storage.loadClips(targetId));
        if (hasSpeechEnergy(audio)) {
          const preliminary = await live?.result;
          // Commands have one authority per utterance. Never execute Vosk and Whisper results twice.
          const transcript = preliminary?.command
            ? { text: preliminary.text, words: [] }
            : await engine.current.transcribe(audio);
          const text = transcript.text;
          if (text) {
            const current = entriesRef.current.find(
              (item) => item.id === targetId,
            );
            if (current) {
              const context = getCommandContext(current);
              const command =
                preliminary?.command ??
                (capturedCommands ? parseCommand(text, context) : undefined);
              if (command) {
                setRecognizedAction(
                  commandCatalog.find((item) => item.id === command)?.label ??
                    text,
                );
                dispatchCommand(command, targetId);
              } else if (capturedMode === "dictation") {
                let passage = annotateProsody(
                  transcriptPassage(transcript, clip.id),
                  audio,
                );
                passage.spans = passage.spans.map((span) => ({
                  ...span,
                  recordingId: clip.recordingId ?? clip.id,
                  recordedStart: (clip.recordingOffset ?? 0) + span.sourceStart,
                  recordedEnd: (clip.recordingOffset ?? 0) + span.sourceEnd,
                }));
                if (replacementRef.current) {
                  const temporary = insertPassage(
                    {
                      ...createEntry(),
                      text: replacementRef.current.passage.text,
                      spans: replacementRef.current.passage.spans,
                      selection: {
                        start: replacementRef.current.passage.text.length,
                        end: replacementRef.current.passage.text.length,
                      },
                    },
                    passage,
                  );
                  const next = {
                    ...replacementRef.current,
                    passage: { text: temporary.text, spans: temporary.spans },
                  };
                  replacementRef.current = next;
                  setReplacement(next);
                } else {
                  updateEntry(targetId, (value) =>
                    insertPassage(value, passage),
                  );
                  if (
                    preferencesRef.current.voiceFeedback &&
                    headphones.connected.current
                  )
                    playFeedback(
                      "commit-buffer",
                      preferencesRef.current.volume,
                    );
                  setShowTimeline(true);
                  const committed = entriesRef.current.find(
                    (item) => item.id === targetId,
                  );
                  if (committed?.lastCommit) {
                    for (const text of commitNotifications(
                      committed,
                      committed.lastCommit,
                      preferencesRef.current,
                    )) {
                      notices.current.push(text, 2200);
                      speakNotice(text);
                    }
                  }
                  if (
                    committed?.lastCommit &&
                    preferencesRef.current.passiveEcho &&
                    headphones.connected.current &&
                    statusRef.current === SpeechStatus.Listening
                  ) {
                    speakRange(committed.lastCommit, undefined, true);
                  }
                }
              }
            }
          }
          clip.transcript = text;
        }
        clip.transcribed = true;
        await storage.saveClip(clip);
      })
      .catch((cause) => {
        showError(
          `Transcription paused: ${errorMessage(cause)} Your original audio is in Recordings; use Retry to transcribe it again.`,
        );
        void stopRef.current();
      })
      .finally(async () => {
        if (live)
          setProvisional((items) =>
            items.filter((item) => item.id !== live.id),
          );
        pendingRef.current -= 1;
        setPending(pendingRef.current);
        if (activeIdRef.current === targetId)
          setClips(await storage.loadClips(targetId).catch(() => []));
      });
  }
  async function prepareVoice() {
    if (statusRef.current === SpeechStatus.Loading) return;
    setError("");
    changeStatus(SpeechStatus.Loading);
    setProgress(0);
    try {
      await Promise.all([engine.current.load(), liveEngine.current.load()]);
      modelReady.current = true;
      changeStatus(SpeechStatus.Ready);
      if (preferencesRef.current.voiceFeedback)
        playFeedback("startup", preferencesRef.current.volume);
    } catch (cause) {
      modelReady.current = false;
      changeStatus(SpeechStatus.Error);
      showError(cause);
    }
  }
  async function startListening(mode: "dictation" | "commands" = "dictation") {
    if (!modelReady.current) {
      await prepareVoice();
      if (!modelReady.current) return;
    }
    if (
      statusRef.current === SpeechStatus.Starting ||
      statusRef.current === SpeechStatus.Listening ||
      !activeIdRef.current
    )
      return;
    setCommandPreview(undefined);
    setHeardSpeech("");
    if (mode === "dictation") stopPlayback();
    listenMode.current = mode;
    setCommandListening(mode === "commands");
    if (mode === "dictation" && preferencesRef.current.voiceFeedback)
      playFeedback("start-listening", preferencesRef.current.volume);
    setError("");
    setMessage("");
    setElapsed(0);
    setShowTimeline(true);
    changeStatus(SpeechStatus.Starting);
    const targetId = activeIdRef.current;
    const recordingId = crypto.randomUUID();
    let recordingOffset = 0;
    let utteranceId = crypto.randomUUID();
    let latestAudioId = utteranceId;
    let lastPartial = "";
    pauseSuggestions.current?.stop();
    pauseSuggestions.current = new PauseSuggestions((kind) => {
      if (
        listenMode.current !== "dictation" ||
        !capture.current ||
        !preferencesRef.current.punctuationSuggestions
      )
        return;
      notices.current.push(
        kind === "paragraph" ? "New paragraph" : "New sentence",
        1800,
      );
      if (preferencesRef.current.voiceFeedback && headphones.connected.current)
        playFeedback(
          kind === "paragraph" ? "paragraph-suggestion" : "sentence-suggestion",
          preferencesRef.current.volume,
        );
    });
    liveEngine.current.onPartial = (id, text) => {
      // Finishing older audio still updates provisional text, but must not revive its command hints.
      if (id === utteranceId) {
        setCommandPreview(text ? { id, entryId: targetId, text } : undefined);
        if (text) setRecognizedAction("");
      }
      if (mode === "commands") {
        // Keep a completed phrase visible until newer speech arrives, while
        // ignoring delayed results belonging to an older utterance.
        if (id === latestAudioId && text) setHeardSpeech(text);
        return;
      }
      if (!text) return;
      const partialKey = `${id}:${text}`;
      if (
        partialKey !== lastPartial &&
        preferencesRef.current.voiceFeedback &&
        headphones.connected.current
      )
        playFeedback("speech-registered", preferencesRef.current.volume);
      lastPartial = partialKey;
      if (mode === "dictation" && preferencesRef.current.punctuationSuggestions)
        pauseSuggestions.current?.heard();
      setProvisional((items) => {
        if (items.some((item) => item.id === id))
          return items.map((item) =>
            item.id === id ? { ...item, text } : item,
          );
        return [...items, { id, entryId: targetId, text }];
      });
    };
    const microphone = new MicrophoneCapture({
      onPitch: (reading) => {
        setLivePitch(reading);
        if (!reading) {
          speakerPitch.current?.reset();
          return;
        }
        const previous = speakerPitch.current?.value;
        const baseline = speakerPitch.current?.add(reading.frequency);
        if (previous === undefined && baseline !== undefined) {
          try {
            localStorage.setItem("lingual-speaker-pitch", String(baseline));
          } catch {
            /* Keep the in-memory baseline. */
          }
        }
      },
      onAudio: (audio) => {
        latestAudioId = utteranceId;
        liveEngine.current.accept(utteranceId, audio);
      },
      onChunk: (audio) => {
        setCommandPreview(undefined);
        const id = utteranceId;
        utteranceId = crypto.randomUUID();
        const enabled = commandsRef.current && capture.current === microphone;
        const result = liveEngine.current.finish(id).then((text) => {
          const current = entriesRef.current.find(
            (item) => item.id === targetId,
          );
          const command =
            enabled && current
              ? parseCommand(text, getCommandContext(current))
              : undefined;
          if (command)
            setRecognizedAction(
              commandCatalog.find((item) => item.id === command)?.label ?? text,
            );
          return { text, command };
        });
        // Attach immediately: persistence/earlier Whisper requests may still be pending when Vosk fails.
        result.catch(() => {});
        enqueue(
          audio,
          targetId,
          undefined,
          {
            id: recordingId,
            offset: recordingOffset,
          },
          { id, result },
        );
        recordingOffset += audio.length / 16000;
      },
      onInterrupted: (text) => {
        setMessage(text);
        void stopRef.current();
      },
    });
    capture.current = microphone;
    try {
      await microphone.start();
      // Microphone permission can reveal output labels that were hidden at page load.
      await headphones.refresh();
      if (
        capture.current === microphone &&
        (statusRef.current as SpeechStatus) === SpeechStatus.Starting
      )
        changeStatus(SpeechStatus.Listening);
    } catch (cause) {
      changeStatus(SpeechStatus.Error);
      const text = errorMessage(cause);
      showError(
        /denied|permission|notallowed/i.test(text)
          ? "Microphone access was denied. Allow the microphone in your browser’s site settings, then try again."
          : text,
      );
    }
  }
  /** Finish entry dictation, then hear commands without adding anything else to it. */
  async function finishEntry() {
    const wasDictating = capture.current && listenMode.current === "dictation";
    await finishListening();
    if (wasDictating) await startListening("commands");
  }
  /** Explicit microphone Stop releases capture; internal transitions may open it again. */
  async function finishListening() {
    resumeSelectedDictation.current = undefined;
    suspendedListening.current = undefined;
    await stopRef.current();
    if (preferencesRef.current.voiceFeedback) {
      playFeedback("stop-listening", preferencesRef.current.volume);
      if (headphones.connected.current)
        playFeedback("save", preferencesRef.current.volume);
    }
  }
  async function stopListening() {
    setCommandPreview(undefined);
    pauseSuggestions.current?.stop();
    if (stopping.current) return stopping.current;
    if (!capture.current && pendingRef.current === 0) return;
    changeStatus(SpeechStatus.Finishing);
    stopping.current = (async () => {
      const microphone = capture.current;
      capture.current = undefined;
      await microphone?.stop();
      await queue.current;
      await writes.current;
      setHeardSpeech("");
      setCommandListening(false);
      changeStatus(modelReady.current ? SpeechStatus.Ready : SpeechStatus.Idle);
    })();
    try {
      await stopping.current;
    } finally {
      stopping.current = undefined;
    }
  }
  stopRef.current = stopListening;

  useEffect(() => {
    let cancelled = false;
    const updateVoices = () =>
      setLocalVoices(
        speechSynthesis
          .getVoices()
          .filter((voice) => voice.localService && voice.lang.startsWith("en")),
      );
    updateVoices();
    speechSynthesis.addEventListener("voiceschanged", updateVoices);
    liveEngine.current.onError = (cause) => {
      modelReady.current = false;
      if (!capture.current) return;
      showError(cause);
      void stopRef.current();
    };
    engine.current.onProgress = (value) => setProgress(Math.round(value));
    storage
      .loadEntries()
      .then((items) => {
        if (cancelled) return;
        let initial = items.length ? items : [createEntry()];
        let restored: Entry | undefined;
        try {
          restored = restoreSession(
            initial,
            localStorage.getItem("lingual-session"),
          );
        } catch {
          // A browser may deny preferences while still allowing IndexedDB entries.
        }
        if (restored)
          initial = initial.map((item) =>
            item.id === restored!.id ? restored! : item,
          );
        entriesRef.current = initial;
        setEntries(initial);
        setActiveId(restored?.id ?? initial[0].id);
        activeIdRef.current = restored?.id ?? initial[0].id;
        setLoaded(true);
        if (!items.length) void storage.saveEntry(initial[0]).catch(showError);
      })
      .catch((cause) => {
        setLoaded(true);
        showError(`Local storage is unavailable: ${errorMessage(cause)}`);
      });
    return () => {
      cancelled = true;
      speechSynthesis.removeEventListener("voiceschanged", updateVoices);
      clearTimeout(browseTimer.current);
      clearTimeout(auditionTimer.current);
      browseClock.current.stop();
      selectionLoop.current.stop();
      pauseSuggestions.current?.stop();
      notices.current.clear();
      void timelinePlayer.current?.dispose();
      void capture.current?.stop();
      engine.current.dispose();
      liveEngine.current.onError = undefined;
      liveEngine.current.dispose();
      releaseOriginalRecording();
      speechSynthesis.cancel();
    };
  }, []);
  useEffect(() => {
    if (!loaded || !entry) return;
    try {
      localStorage.setItem(
        "lingual-session",
        JSON.stringify({
          entryId: entry.id,
          selection: entry.selection,
          selectionScale: entry.selectionScale,
        }),
      );
    } catch {
      // Entry/audio persistence is independent; private browsing can deny session preferences.
    }
  }, [
    loaded,
    entry?.id,
    entry?.selection.start,
    entry?.selection.end,
    entry?.selectionScale,
  ]);
  useEffect(() => {
    if (!loaded || showTimeline || !entry) return;
    const visible = displaySelection(
      entryPresentation(entry, preferencesRef.current),
      entry.selection,
    );
    textarea.current?.setSelectionRange(visible.start, visible.end);
  }, [loaded, activeId, showTimeline]);
  useEffect(() => {
    if (!activeId) return;
    let cancelled = false;
    storage
      .loadClips(activeId)
      .then((items) => {
        if (!cancelled) setClips(items);
      })
      .catch(showError);
    return () => {
      cancelled = true;
    };
  }, [activeId]);
  useEffect(() => {
    if (!recording) return;
    const timer = setInterval(() => setElapsed((value) => value + 1), 1000);
    return () => clearInterval(timer);
  }, [recording]);
  useEffect(() => {
    // Reconcile ongoing audio when the system route changes, not just future actions.
    if (!headphonesConnected && echoRequiresHeadphones.current) {
      ++echoGeneration.current;
      speechSynthesis.cancel();
      echoRequiresHeadphones.current = false;
      setEchoing(false);
      setEchoPaused(false);
      setPlaybackRange(undefined);
    }
    if (browseRef.current && !browseRef.current.paused)
      void browseRunner.current().catch(showError);
    if (
      !headphonesConnected &&
      !browseRef.current &&
      capture.current &&
      listenMode.current === "commands" &&
      (timelinePlaying || (echoing && !echoRequiresHeadphones.current))
    )
      void suspendPlaybackListening().catch(showError);
  }, [headphonesConnected]);
  useEffect(() => {
    if (!pending || !headphonesConnected || !preferences.voiceFeedback) return;
    const sound = new Audio(`${import.meta.env.BASE_URL}sounds/processing.wav`);
    sound.loop = true;
    sound.volume = 0.02 * preferences.volume;
    void sound.play().catch(() => {});
    return () => {
      sound.pause();
      sound.removeAttribute("src");
      sound.load();
    };
  }, [
    Boolean(pending),
    headphonesConnected,
    preferences.voiceFeedback,
    preferences.volume,
  ]);
  useEffect(() => {
    if (!dialog || !["delete", "export"].includes(dialog)) return;
    if (preferencesRef.current.voiceFeedback)
      playFeedback("dialog", preferencesRef.current.volume);
    speakNotice(
      dialog === "delete"
        ? "Delete this entry? Say delete or cancel."
        : "Choose export format. Say export audio, export text, or cancel.",
    );
  }, [dialog]);
  useEffect(() => {
    if (!playbackRange) return;
    const word = document.querySelector<HTMLElement>(
      `[data-word-start="${playbackRange.start}"]`,
    );
    const bounds = word?.getBoundingClientRect();
    if (bounds && (bounds.top < 0 || bounds.bottom > window.innerHeight))
      word?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [playbackRange?.start]);
  useEffect(() => {
    if (!recording || !showTimeline) return;
    // Follow new speech at its insertion point, including a gray buffer below the fold.
    const provisional = document.querySelector<HTMLElement>(
      ".provisional-speech",
    );
    const words = Array.from(
      document.querySelectorAll<HTMLElement>("[data-word-start]"),
    );
    const committed = words
      .reverse()
      .find(
        (word) =>
          Number(word.dataset.wordStart) < (entry?.selection.start ?? 0),
      );
    (provisional ?? committed)?.scrollIntoView({ block: "nearest" });
  }, [
    recording,
    showTimeline,
    entry?.text,
    liveWords.map((item) => item.text).join(" "),
  ]);
  useEffect(() => {
    if (browse?.scope === "list")
      document
        .querySelector(".entry-card.selected")
        ?.scrollIntoView({ block: "nearest" });
  }, [browse?.scope, browse?.index]);
  useEffect(() => {
    if (!headphonesConnected || !modelReady.current) return;
    const modal = Boolean(
      replacement || dialog === "delete" || dialog === "export",
    );
    const library = mobileLibrary || dialog === "help";
    if (!modal && (!library || (recording && !commandListening))) return;
    const name = modal ? "modal-ambience.wav" : "nature-ambience.mp3";
    const ambience = new Audio(`${import.meta.env.BASE_URL}sounds/${name}`);
    ambience.loop = true;
    ambience.volume = 0.02 * preferences.volume;
    void ambience.play().catch(() => {});
    return () => {
      ambience.pause();
      ambience.removeAttribute("src");
      ambience.load();
    };
  }, [
    headphonesConnected,
    preferences.volume,
    mobileLibrary,
    dialog,
    Boolean(replacement),
    recording,
    commandListening,
  ]);
  useEffect(() => {
    let cancelled = false;
    const selected = entry && entry.selection.end > entry.selection.start;
    const reconcile = async () => {
      selectionLoop.current.stop();
      if (selectionOwnsAudio.current) stopPlayback();
      if (replacementRef.current) {
        // Selection listens for commands; accepting replacement dictation must switch that same microphone back.
        if (
          (capture.current && listenMode.current === "commands") ||
          (stopping.current && resumeSelectedDictation.current === activeId)
        ) {
          await stopRef.current();
          if (!cancelled) await startListening("dictation");
        }
        return;
      }
      if (browseRef.current) return;
      if (!selected) {
        const resumeId = resumeSelectedDictation.current;
        resumeSelectedDictation.current = undefined;
        if (resumeId === activeId && !document.hidden) {
          await stopRef.current();
          if (!cancelled) await startListening("dictation");
        }
        return;
      }
      if (capture.current && listenMode.current === "dictation") {
        resumeSelectedDictation.current = activeId;
        await stopRef.current();
      } else if (stopping.current) await stopping.current;
      if (cancelled) return;
      if (
        resumeSelectedDictation.current === activeId &&
        commandsRef.current &&
        !capture.current
      )
        await startListening("commands");
      if (cancelled || !headphones.connected.current) return;
      const current = entriesRef.current.find((item) => item.id === activeId);
      if (current && hasCompleteAudio(copyPassage(current, current.selection)))
        repeatSelection(current.selection);
    };
    void reconcile().catch(showError);
    return () => {
      cancelled = true;
      selectionLoop.current.stop();
    };
  }, [
    activeId,
    entry?.selection.start,
    entry?.selection.end,
    Boolean(browse),
    Boolean(replacement),
    headphonesConnected,
  ]);
  useEffect(() => {
    const handleSelection = () => {
      const target = textarea.current;
      if (!target || document.activeElement !== target) return;
      updateEntry(
        activeIdRef.current,
        (current) => ({
          ...current,
          selection: sourceSelection(
            entryPresentation(current, preferencesRef.current),
            { start: target.selectionStart, end: target.selectionEnd },
          ),
          selectionScale: (() => {
            const range = sourceSelection(
              entryPresentation(current, preferencesRef.current),
              { start: target.selectionStart, end: target.selectionEnd },
            );
            return range.start === current.selection.start &&
              range.end === current.selection.end
              ? current.selectionScale
              : undefined;
          })(),
        }),
        false,
      );
    };
    document.addEventListener("selectionchange", handleSelection);
    return () =>
      document.removeEventListener("selectionchange", handleSelection);
  }, []);
  useEffect(() => {
    const onHidden = () => {
      if (document.hidden && capture.current) {
        setMessage(
          "Listening paused when you left this tab. Press Start listening to resume.",
        );
        void stopRef.current();
      }
    };
    const beforeUnload = (event: BeforeUnloadEvent) => {
      if (capture.current || pendingRef.current) {
        event.preventDefault();
      }
    };
    document.addEventListener("visibilitychange", onHidden);
    window.addEventListener("beforeunload", beforeUnload);
    return () => {
      document.removeEventListener("visibilitychange", onHidden);
      window.removeEventListener("beforeunload", beforeUnload);
    };
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem("lingual-voice-actions", String(commands));
    } catch (cause) {
      showError(cause);
    }
  }, [commands]);

  const displayingRecordedPitch = Boolean(
    playbackRange && !echoing && !echoPaused,
  );
  const displayedPitch = displayingRecordedPitch
    ? playbackPitch
    : livePitch?.frequency;
  const filtered = entries.filter((item) =>
    `${entryTitle(item)} ${item.text}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  );
  const audioTime = entry
    ? selectionAudioTime(entry, preferences.omitSilences)
    : { start: 0, end: 0 };
  const displayedWords = new Map(
    entry
      ? presentationFragments(entry, preferences, {
          start: 0,
          end: entry.text.length,
        }).map((fragment) => [fragment.start, fragment.text])
      : [],
  );
  const performSelection = (action: string) => {
    const current = entriesRef.current.find(
      (item) => item.id === activeIdRef.current,
    );
    if (!current) return;
    const command = parseCommand(action, getCommandContext(current));
    if (command) dispatchCommand(command);
  };
  return (
    <div className="app-shell">
      <aside
        id="entry-library"
        className={`library ${mobileLibrary ? "mobile-open" : ""}`}
        aria-label="Entry library"
        aria-hidden={compactLayout && !mobileLibrary}
        inert={compactLayout && !mobileLibrary}
      >
        <a
          className="brand"
          href="#"
          onClick={(event) => {
            event.preventDefault();
            setMobileLibrary(false);
          }}
        >
          <img
            className="brand-wordmark"
            src={`${import.meta.env.BASE_URL}brand/wordmark-light.png`}
            alt="Lingual"
            width="1687"
            height="600"
          />
          <span className="local-badge">LOCAL</span>
        </a>
        <Button
          tooltip={"Close the entry library and return to your entry."}
          className="mobile-library-close"
          aria-label="Close entry library"
          onClick={() => setMobileLibrary(false)}
        >
          <X size={20} />
        </Button>
        <Button
          tooltip={"Create an empty entry, then speak to add words."}
          className="new-entry"
          onClick={newEntry}
          disabled={busy || !loaded}
        >
          <Plus size={18} /> New entry
        </Button>
        <label className="search">
          <Search size={16} />
          <input
            aria-label="Search entries"
            placeholder="Find an entry…"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
        </label>
        <div className="library-browse">
          <Button
            tooltip={
              "Preview the current entry repeatedly. Use Next or Previous to choose another entry."
            }
            disabled={busy}
            onClick={() => dispatchCommand(Command.WALK_ENTRY_LIST)}
          >
            Walk entries
          </Button>
          <Button
            tooltip={"Preview entries in order, advancing automatically."}
            disabled={busy}
            onClick={() => dispatchCommand(Command.RUN_ENTRY_LIST)}
          >
            Run entries
          </Button>
        </div>
        <div className="library-heading">
          <span>YOUR ENTRIES</span>
          <span>{entries.length}</span>
        </div>
        <nav className="entry-list" aria-label="Entries">
          {filtered.map((item) => (
            <Button
              tooltip={`Open ${entryTitle(item)}.`}
              key={item.id}
              disabled={busy}
              className={`entry-card ${activeId === item.id ? "selected" : ""} ${recording && !commandListening && activeId === item.id ? "entry-recording" : ""}`}
              onClick={() => selectEntry(item.id)}
            >
              <div className="entry-card-top">
                <FileText size={15} />
                <time>
                  {new Date(item.updatedAt).toLocaleDateString(undefined, {
                    month: "short",
                    day: "numeric",
                  })}
                </time>
                {activeId === item.id && <span className="entry-dot" />}
              </div>
              <strong>{entryTitle(item)}</strong>
              <p>
                {punctuationPresentation(
                  item.text,
                  preferences.punctuationSuggestions,
                ).text.trim() || "A thought waiting to happen."}
              </p>
            </Button>
          ))}
          {query && !filtered.length && (
            <p className="empty-search">No matching entries.</p>
          )}
        </nav>
        <div className="library-bottom">
          <div className="local-note">
            <ShieldCheck size={19} />
            <div>
              <strong>Your entries stay in this browser.</strong>
            </div>
          </div>
          <Button
            tooltip={"Open instructions and the voice-action dictionary."}
            onClick={() => setDialog("help")}
          >
            <CircleHelp size={17} /> Help
          </Button>
          <Button
            tooltip={
              "Change speech, playback, formatting, and storage preferences."
            }
            onClick={() => setDialog("settings")}
          >
            <Settings2 size={17} /> Settings
          </Button>
          <div className="version">
            <span>v0.1</span>
          </div>
        </div>
      </aside>
      {compactLayout && mobileLibrary && (
        <div
          className="library-backdrop"
          aria-hidden="true"
          onClick={() => setMobileLibrary(false)}
        />
      )}
      <main className="workspace" inert={compactLayout && mobileLibrary}>
        <header className="topbar">
          <div className="breadcrumb">
            <Button
              tooltip={"Show or hide the entry library."}
              className="mobile-library-toggle"
              onClick={() => setMobileLibrary((value) => !value)}
              aria-label="Toggle entry library"
              aria-controls="entry-library"
              aria-expanded={mobileLibrary}
            >
              <BookOpen size={20} />
            </Button>
            <span>{entry ? entryTitle(entry) : "Loading…"}</span>
          </div>
          <div className="topbar-actions">
            <span className={`save-state ${!saved ? "unsaved" : ""}`}>
              <span />
              {saved ? "Saved on this device" : "Saving…"}
            </span>
            <Button
              tooltip={
                "Change speech, playback, formatting, and storage preferences."
              }
              className="icon-button"
              onClick={() => setDialog("settings")}
              aria-label="Settings"
            >
              <Settings2 size={18} />
            </Button>
            <img
              className="app-brand-icon"
              src={`${import.meta.env.BASE_URL}brand/app-icon.png`}
              alt="Lingual app icon"
              width="32"
              height="32"
            />
          </div>
        </header>
        <div className="work-area">
          <section className="editor-column">
            <section className="editor-sheet" aria-label="Entry editor">
              <div className="sheet-heading">
                <div className="sheet-date">
                  <span />
                  {entry &&
                    new Date(entry.createdAt).toLocaleDateString(undefined, {
                      weekday: "long",
                      month: "long",
                      day: "numeric",
                    })}
                </div>
                <div className="sheet-actions">
                  <Button
                    tooltip={"Download this entry as a text file."}
                    className="icon-button"
                    onClick={exportText}
                    disabled={!entry?.text}
                    aria-label="Export text"
                  >
                    <ArrowDownToLine size={17} />
                  </Button>
                  <div className="menu-wrapper">
                    <Button
                      tooltip={
                        "Open export, recordings, and delete actions for this entry."
                      }
                      className="icon-button"
                      onClick={() => setMenu((value) => !value)}
                      aria-label="Entry options"
                    >
                      <MoreHorizontal size={19} />
                    </Button>
                    {menu && (
                      <div className="popover">
                        <Button
                          tooltip={"Download this entry as a text file."}
                          onClick={() => {
                            exportText();
                            setMenu(false);
                          }}
                        >
                          Export text
                        </Button>
                        <Button
                          tooltip={
                            "Show the original audio saved for this entry."
                          }
                          onClick={() => {
                            setShowRecordings(true);
                            setMenu(false);
                          }}
                        >
                          Show recordings
                        </Button>
                        <Button
                          tooltip={
                            "Open the confirmation to delete this entry and its recordings."
                          }
                          disabled={busy}
                          onClick={() => {
                            setDialog("delete");
                            setMenu(false);
                          }}
                        >
                          <Trash2 size={14} /> Delete entry
                        </Button>
                      </div>
                    )}
                  </div>
                </div>
              </div>
              <h1 className="entry-title">
                {entry ? entryTitle(entry) : "Loading…"}
              </h1>
              <textarea
                ref={textarea}
                style={{ display: showTimeline ? "none" : undefined }}
                aria-label="Entry text"
                placeholder={
                  "Choose Start entry to record a new entry, or Resume entry to add here."
                }
                value={entry ? entryPresentation(entry, preferences).text : ""}
                readOnly
                inputMode="none"
                spellCheck={false}
                onClick={() => {
                  if (browseRef.current) dispatchCommand(Command.EXIT_WALK);
                }}
                onSelect={(event) => {
                  const target = event.currentTarget;
                  updateEntry(
                    activeId,
                    (current) => ({
                      ...current,
                      selection: sourceSelection(
                        entryPresentation(current, preferences),
                        {
                          start: target.selectionStart,
                          end: target.selectionEnd,
                        },
                      ),
                    }),
                    false,
                  );
                }}
                onKeyDown={(event) => {
                  if (
                    (event.metaKey || event.ctrlKey) &&
                    event.key.toLowerCase() === "z"
                  ) {
                    event.preventDefault();
                    dispatchCommand(
                      event.shiftKey
                        ? Command.REDO_CHANGE
                        : Command.UNDO_CHANGE,
                    );
                  }
                }}
              />
              {showTimeline && entry && (
                <div
                  className="timeline-text"
                  aria-label="Audio-linked transcript"
                  style={{ whiteSpace: "pre-wrap" }}
                  onClick={(event) => {
                    if (
                      event.target === event.currentTarget &&
                      browseRef.current
                    )
                      dispatchCommand(Command.EXIT_WALK);
                  }}
                >
                  {
                    textFragments(entry.text).reduce<{
                      elements: React.ReactNode[];
                      offset: number;
                      provisionalInserted: boolean;
                    }>(
                      (result, fragment, index) => {
                        const word = fragment.text;
                        const start = fragment.start;
                        const end = fragment.end;
                        result.offset = end;
                        if (
                          !result.provisionalInserted &&
                          start >= entry.selection.start
                        ) {
                          result.elements.push(provisionalNode);
                          result.provisionalInserted = true;
                        }
                        if (!containsWords(word)) {
                          result.elements.push(
                            displayGap(entry, start, end, preferences),
                          );
                          return result;
                        }
                        const audio = entry.spans.find(
                          (span) => span.start < end && span.end > start,
                        );
                        const selected =
                          entry.selection.start < end &&
                          entry.selection.end > start;
                        const playing =
                          playbackRange &&
                          playbackRange.start < end &&
                          playbackRange.end > start;
                        result.elements.push(
                          <Button
                            key={index}
                            data-word-start={start}
                            className={`transcript-word ${audio ? "has-audio" : "missing-audio"} ${audio && audio.rate !== 1 ? "word-transformed" : ""} ${selected ? "word-selected" : ""} ${playing ? "word-playing" : ""} ${audio?.emphasized && preferences.formattingSuggestions ? "emphasized" : ""}`}
                            aria-pressed={selected}
                            tooltip={
                              audio
                                ? `Recorded · ${audio.sourceStart.toFixed(2)}–${audio.sourceEnd.toFixed(2)}s · ${audio.rate}×${audio.pitch ? ` · ${Math.round(audio.pitch)} Hz` : ""}${audio.power !== undefined ? ` · ${Math.round(audio.power)} dB` : ""}${audio.speakingRate ? ` · ${audio.speakingRate.toFixed(1)} words/s` : ""}`
                                : "Missing original recording"
                            }
                            onClick={(event) => {
                              if (browseRef.current) {
                                dispatchCommand(Command.EXIT_WALK);
                                return;
                              }
                              if (
                                !event.shiftKey &&
                                playbackRange &&
                                !echoing &&
                                !echoPaused &&
                                timelinePlayer.current?.seekToWord(start)
                              )
                                return;
                              updateEntry(
                                activeId,
                                (value) => ({
                                  ...value,
                                  selectionScale: undefined,
                                  selection: {
                                    start: event.shiftKey
                                      ? Math.min(value.selection.start, start)
                                      : start,
                                    end: event.shiftKey
                                      ? Math.max(value.selection.end, end)
                                      : end,
                                  },
                                }),
                                false,
                              );
                              if (!event.shiftKey && !playbackRange)
                                void auditionWord(start).catch(showError);
                            }}
                          >
                            {displayedWords.get(start) ??
                              displayWord(word, Boolean(audio), preferences)}
                          </Button>,
                        );
                        return result;
                      },
                      { elements: [], offset: 0, provisionalInserted: false },
                    ).elements
                  }
                  {entry.selection.start >= entry.text.length &&
                    provisionalNode}
                  {!entry.text && !liveWords.length && (
                    <span className="muted">
                      Your spoken words will appear here.
                    </span>
                  )}
                </div>
              )}
              {!showTimeline && provisionalNode}
              {suggestions.length ? (
                <CommandCompletions suggestions={suggestions} />
              ) : (
                <SelectionSuggestions
                  commands={
                    discoveryContext
                      ? selectionSuggestions(discoveryContext)
                      : []
                  }
                  onAction={dispatchCommand}
                />
              )}
              {recognizedAction && (
                <div
                  className="recognized-action"
                  role="status"
                  aria-label="Voice action recognized"
                >
                  <span aria-hidden="true">✓</span> {recognizedAction}
                </div>
              )}
              {(recording || displayingRecordedPitch) && (
                <div className="pitch-readout" role="status" aria-label="Pitch">
                  <span>Pitch</span>
                  <strong>{pitchNote(displayedPitch) || "—"}</strong>
                  {displayedPitch !== undefined && (
                    <span>{Math.round(displayedPitch!)} Hz</span>
                  )}
                </div>
              )}
              {!dialog && <HeadphoneReminder message={headphoneMessage} />}
              <section
                className={`voice-console ${recording ? "is-recording" : ""}`}
                aria-label="Voice controls"
              >
                <div className="voice-console-main">
                  {recording && commandListening && (
                    <section
                      className="listening-only"
                      aria-label="Listening only"
                    >
                      <strong>Listening only</strong>
                      <p>Nothing is being added to this entry.</p>
                      <div
                        aria-label="Heard speech"
                        aria-live="polite"
                        className="heard-speech"
                      >
                        {heardSpeech || "Listening…"}
                      </div>
                    </section>
                  )}
                  {(recording ||
                    pending > 0 ||
                    [
                      SpeechStatus.Loading,
                      SpeechStatus.Starting,
                      SpeechStatus.Finishing,
                    ].includes(status)) && (
                    <div className="voice-feedback">
                      <div className="voice-console-top">
                        <div className="voice-label">
                          <span
                            className={`status-light ${recording ? "active" : ""}`}
                          />
                          <strong>
                            {recording
                              ? commandListening
                                ? "Microphone on"
                                : "Recording this entry"
                              : status === SpeechStatus.Loading
                                ? "Preparing your private speech engine"
                                : status === SpeechStatus.Starting
                                  ? "Waiting for microphone access"
                                  : status === SpeechStatus.Finishing
                                    ? "Saving the last of your thoughts"
                                    : pending
                                      ? "Turning speech into words"
                                      : ""}
                          </strong>
                        </div>
                      </div>
                      <div className="voice-meter">
                        {recording && (
                          <span className="recording-time">
                            {formatTime(elapsed)}
                          </span>
                        )}
                      </div>
                    </div>
                  )}
                  <Button
                    tooltip={
                      recording
                        ? "Stop the microphone and finish transcribing the captured audio."
                        : status === SpeechStatus.Starting
                          ? "Cancel microphone startup."
                          : status === SpeechStatus.Loading
                            ? "Preparing speech recognition on this device."
                            : status === SpeechStatus.Finishing
                              ? "Finishing the captured audio before another recording."
                              : modelReady.current
                                ? "Listen without adding speech or recordings to an entry."
                                : "Load the speech models and start listening without changing the selected entry."
                    }
                    className={`listen-button ${recording ? "stop microphone-control" : ""}`}
                    disabled={
                      !entry ||
                      status === SpeechStatus.Loading ||
                      status === SpeechStatus.Finishing ||
                      (pending > 0 && !recording)
                    }
                    onClick={() => {
                      if (recording || status === SpeechStatus.Starting)
                        void finishListening();
                      else void startListening("commands");
                    }}
                  >
                    {recording ? (
                      <Square size={15} fill="currentColor" />
                    ) : status === SpeechStatus.Loading ||
                      status === SpeechStatus.Finishing ? (
                      <LoaderCircle size={18} className="spin" />
                    ) : (
                      <Mic size={18} />
                    )}
                    <span>
                      {recording
                        ? "Stop listening"
                        : status === SpeechStatus.Starting
                          ? "Cancel"
                          : status === SpeechStatus.Loading
                            ? `Downloading · ${progress}%`
                            : status === SpeechStatus.Finishing
                              ? "Finishing…"
                              : modelReady.current
                                ? "Start listening"
                                : "Enable voice"}
                    </span>
                  </Button>
                  {modelReady.current && (
                    <div className="entry-recording-actions">
                      {recording && !commandListening ? (
                        <Button
                          className="listen-button"
                          tooltip="Save this entry’s recording and return to listening only."
                          onClick={() => void finishEntry()}
                        >
                          <Square size={15} fill="currentColor" /> Stop entry
                        </Button>
                      ) : (
                        <>
                          <Button
                            className="listen-button"
                            disabled={busy && !commandListening}
                            tooltip="Create a new entry and record your next words into it."
                            onClick={() =>
                              void performEffect({
                                kind: "new-entry",
                                startRecording: true,
                              })
                            }
                          >
                            <Plus size={18} /> Start entry
                          </Button>
                          <Button
                            disabled={busy && !commandListening}
                            tooltip="Add your next spoken words and audio to the selected entry."
                            onClick={() =>
                              void performEffect({ kind: "listen" })
                            }
                          >
                            Resume entry
                          </Button>
                        </>
                      )}
                    </div>
                  )}
                  <div className="speech-details">
                    {(pending > 0 || !modelReady.current) && (
                      <span className="speech-status">
                        {pending
                          ? `${pending} audio passage${pending === 1 ? "" : "s"} waiting for transcription`
                          : "First-use download: ~109 MB"}
                      </span>
                    )}
                    <div className="speech-reassurance">
                      <span>No account or subscription</span>
                      <span>Transcribed on your device</span>
                    </div>
                  </div>
                </div>
                <div className="voice-console-bottom">
                  <div className="voice-actions-copy">
                    <strong>Voice actions</strong>
                    <span>Speak commands to edit and navigate.</span>
                  </div>
                  <Button
                    tooltip={
                      commands
                        ? "Turn voice actions off to dictate command phrases as entry content."
                        : "Turn voice actions on to control Lingual by speaking commands."
                    }
                    onClick={() => {
                      setCommandPreview(undefined);
                      commandsRef.current = !commands;
                      setCommands(!commands);
                    }}
                    className={`command-toggle ${commands ? "enabled" : ""}`}
                    aria-pressed={commands}
                    aria-label={`Voice actions ${commands ? "on" : "off"}`}
                  >
                    <span /> {commands ? "On" : "Off"}
                  </Button>
                </div>
              </section>
              <div className="editor-toolbar">
                <div className="editing-tools">
                  <Button
                    tooltip={
                      "Undo the last edit, restoring its words and original audio."
                    }
                    className="icon-button"
                    disabled={!entry?.history.length}
                    aria-label="Undo"
                    onClick={() => dispatchCommand(Command.UNDO_CHANGE)}
                  >
                    <Undo2 size={17} />
                  </Button>
                  <Button
                    tooltip={"Reapply the last undone edit with its audio."}
                    className="icon-button"
                    disabled={!entry?.future.length}
                    aria-label="Redo"
                    onClick={() => dispatchCommand(Command.REDO_CHANGE)}
                  >
                    <Redo2 size={17} />
                  </Button>
                  <span className="tool-divider" />
                  <Button
                    tooltip={
                      "Copy selected words and their recordings to the Lingual clipboard."
                    }
                    className="icon-button"
                    disabled={
                      !entry || entry.selection.start === entry.selection.end
                    }
                    onClick={() => performSelection("copy selection")}
                    aria-label="Copy selection"
                  >
                    <Copy size={16} />
                  </Button>
                  <Button
                    tooltip={
                      "Move selected words and their recordings to the Lingual clipboard."
                    }
                    className="icon-button"
                    disabled={
                      !entry || entry.selection.start === entry.selection.end
                    }
                    onClick={() => performSelection("cut selection")}
                    aria-label="Cut selection"
                  >
                    <Scissors size={16} />
                  </Button>
                  <Button
                    tooltip={
                      "Insert the Lingual clipboard with its original audio at your selection."
                    }
                    className="icon-button"
                    disabled={
                      !audioClipboard.current.text ||
                      !hasCompleteAudio(audioClipboard.current)
                    }
                    onClick={() => performSelection("paste")}
                    aria-label="Paste Lingual clipboard"
                  >
                    <ClipboardPaste size={16} />
                  </Button>
                </div>
                <span className="word-count">
                  {wordCount(entry?.text ?? "")} words<span> · </span>
                  <span aria-label="Audio position">
                    {formatTime(audioTime.start)}
                    {audioTime.end !== audioTime.start
                      ? `–${formatTime(audioTime.end)}`
                      : ""}{" "}
                    audio
                  </span>
                </span>
              </div>
            </section>
            <div
              className="parity-toolbar"
              aria-label="Audio and selection actions"
            >
              <div className="view-switch">
                <Button
                  tooltip={
                    "Read and select the transcript. New words must be spoken; typing is disabled."
                  }
                  className={!showTimeline ? "active" : ""}
                  onClick={() => setShowTimeline(false)}
                >
                  Transcript
                </Button>
                <Button
                  tooltip={
                    "Show individual recorded words. Click a word or Shift-click a range to select; hover for recording times."
                  }
                  className={showTimeline ? "active" : ""}
                  onClick={() => setShowTimeline(true)}
                >
                  Audio-linked view
                </Button>
              </div>
              <select
                aria-label="Selection action"
                value=""
                onChange={(event) => {
                  dispatchCommand(event.target.value as Command);
                }}
              >
                <option value="" disabled>
                  Selection actions
                </option>
                {[
                  Command.SELECT_WORD,
                  Command.SELECT_SENTENCE,
                  Command.SELECT_PARAGRAPH,
                  Command.ENTER_SELECTION,
                  Command.EXPAND_SELECTION,
                  Command.REDUCE_SELECTION,
                  Command.SHIFT_ANCHOR_LEFT,
                  Command.SHIFT_ANCHOR_RIGHT,
                  Command.SHIFT_FOCUS_LEFT,
                  Command.SHIFT_FOCUS_RIGHT,
                  Command.SHIFT_SELECTION_FORWARD,
                  Command.SHIFT_SELECTION_BACKWARD,
                  Command.REMOVE_SELECTION,
                  Command.UPDATE_SELECTION,
                  Command.DELETE_SELECTION,
                  Command.COPY_SELECTION,
                  Command.CUT_SELECTION,
                  Command.PASTE_CLIPBOARD,
                  Command.PLAY_SELECTION,
                  Command.ECHO_SELECTION,
                  Command.EXPORT_SELECTION,
                  Command.INCREASE_SELECTION_RATE,
                  Command.DECREASE_SELECTION_RATE,
                ].map((command) => (
                  <option value={command} key={command}>
                    {commandCatalog.find((item) => item.id === command)?.label}
                  </option>
                ))}
              </select>
              <Button
                tooltip={"Play this entry using your original recorded voice."}
                disabled={!entry?.text}
                onClick={() => dispatchCommand(Command.PLAY_ENTRY)}
              >
                <Play size={13} /> Play
              </Button>
              <Button
                tooltip={
                  "Repeat the current recorded word. Use Next or Previous to move through the entry."
                }
                disabled={!entry?.text}
                onClick={() => dispatchCommand(Command.WALK_ENTRY)}
              >
                Walk
              </Button>
              <Button
                tooltip={
                  "Play recorded words in order, advancing automatically."
                }
                disabled={!entry?.text}
                onClick={() => dispatchCommand(Command.RUN_ENTRY)}
              >
                Run
              </Button>
            </div>
            {(timelinePlaying ||
              echoing ||
              echoPaused ||
              playbackPosition > 0) && (
              <div
                className="playback-controls"
                role="group"
                aria-label="Playback controls"
              >
                <div className="playback-transport">
                  <Button
                    tooltip={"Move recorded playback backward by ten seconds."}
                    onClick={() =>
                      dispatchCommand(Command.SKIP_PLAYBACK_BACKWARD)
                    }
                  >
                    −10s
                  </Button>
                  <Button
                    tooltip={
                      echoing
                        ? "Pause the synthesized read-back."
                        : echoPaused
                          ? "Resume the synthesized read-back."
                          : timelinePlaying
                            ? "Pause recorded playback."
                            : "Resume recorded playback."
                    }
                    className="playback-primary"
                    aria-label={
                      echoing
                        ? "Pause echo"
                        : echoPaused
                          ? "Resume echo"
                          : timelinePlaying
                            ? "Pause playback"
                            : "Resume playback"
                    }
                    onClick={() =>
                      dispatchCommand(
                        echoing
                          ? Command.PAUSE_ECHO
                          : echoPaused
                            ? Command.RESUME_ECHO
                            : timelinePlaying
                              ? Command.PAUSE_PLAYBACK
                              : Command.RESUME_PLAYBACK,
                      )
                    }
                  >
                    {timelinePlaying || echoing ? (
                      <Pause size={15} />
                    ) : (
                      <Play size={15} />
                    )}
                  </Button>
                  <Button
                    tooltip={"Stop playback and clear its word highlight."}
                    aria-label="Stop playback"
                    onClick={() => dispatchCommand(Command.STOP_PLAYBACK)}
                  >
                    <Square size={13} />
                  </Button>
                  <Button
                    tooltip={"Move recorded playback forward by ten seconds."}
                    onClick={() =>
                      dispatchCommand(Command.SKIP_PLAYBACK_FORWARD)
                    }
                  >
                    +10s
                  </Button>
                </div>
                <div className="playback-details">
                  <span
                    className="playback-time"
                    aria-label="Playback position"
                  >
                    {formatTime(playbackPosition)}
                  </span>
                  <div
                    className="playback-speed"
                    role="group"
                    aria-label="Playback speed controls"
                  >
                    <Button
                      tooltip={
                        "Slow down the current playback or synthesized read-back."
                      }
                      onClick={() =>
                        dispatchCommand(
                          echoing || echoPaused
                            ? Command.DECREASE_ECHO_RATE
                            : Command.DECREASE_PLAYBACK_RATE,
                        )
                      }
                    >
                      −
                    </Button>
                    <span>
                      {(echoing || echoPaused
                        ? preferences.echoRate
                        : preferences.playbackRate
                      ).toFixed(1)}
                      ×
                    </span>
                    <Button
                      tooltip={
                        "Speed up the current playback or synthesized read-back."
                      }
                      onClick={() =>
                        dispatchCommand(
                          echoing || echoPaused
                            ? Command.INCREASE_ECHO_RATE
                            : Command.INCREASE_PLAYBACK_RATE,
                        )
                      }
                    >
                      +
                    </Button>
                  </div>
                </div>
              </div>
            )}
            {browse && (
              <div className="browse-bar" role="status">
                <strong>
                  {browse.mode === "run" ? "Running" : "Walking"}{" "}
                  {browse.scope === "list" ? "entries" : browse.scope} ·{" "}
                  {browse.index + 1}
                </strong>
                <Button
                  tooltip={
                    "Move to the previous word or entry in this walk or run."
                  }
                  onClick={() =>
                    dispatchCommand(Command.SHIFT_PREVIOUS_WALK_ELEMENT)
                  }
                >
                  Previous
                </Button>
                <Button
                  tooltip={
                    "Move to the next word or entry in this walk or run."
                  }
                  onClick={() =>
                    dispatchCommand(Command.SHIFT_NEXT_WALK_ELEMENT)
                  }
                >
                  Next
                </Button>
                <Button
                  tooltip={"Pause this walk or run at its current position."}
                  onClick={() => dispatchCommand(Command.PAUSE_RUN)}
                >
                  Pause
                </Button>
                <Button
                  tooltip={"End this walk or run and return to the entry."}
                  onClick={() => dispatchCommand(Command.EXIT_WALK)}
                >
                  Exit
                </Button>
              </div>
            )}
            {replacement && (
              <section className="replacement-panel">
                <h3>Update selection</h3>
                <p>
                  Replace “
                  {entry?.text.slice(
                    replacement.range.start,
                    replacement.range.end,
                  )}
                  ”
                </p>
                <textarea
                  aria-label="Replacement text"
                  placeholder="Start listening and speak a replacement…"
                  value={
                    punctuationPresentation(
                      replacement.passage.text,
                      preferences.punctuationSuggestions,
                    ).text
                  }
                  readOnly
                  inputMode="none"
                />
                <div>
                  <Button
                    tooltip={
                      "Replace the selected words and audio with your spoken draft."
                    }
                    disabled={!replacement.passage.text}
                    onClick={() =>
                      dispatchCommand(Command.ACCEPT_SELECTION_UPDATE)
                    }
                  >
                    Accept replacement
                  </Button>
                  <Button
                    tooltip={
                      "Clear the spoken draft and record another attempt. Keep the original selection."
                    }
                    onClick={() =>
                      dispatchCommand(Command.REDO_SELECTION_UPDATE)
                    }
                  >
                    Redo replacement
                  </Button>
                  <Button
                    tooltip={
                      "Discard the draft and keep the original words and recording."
                    }
                    onClick={() =>
                      dispatchCommand(Command.CANCEL_SELECTION_UPDATE)
                    }
                  >
                    Cancel replacement
                  </Button>
                </div>
              </section>
            )}
            {error && (
              <div className="notice error" role="alert">
                <span>{error}</span>
                <Button
                  tooltip={"Dismiss this error message."}
                  aria-label="Dismiss error"
                  onClick={() => setError("")}
                >
                  <X size={16} />
                </Button>
              </div>
            )}
            {exporting && <div role="status">Exporting audio…</div>}
            {welcomeLoading && (
              <div role="status">Loading the original welcome recording…</div>
            )}
            {(notice || message) && (
              <div className="notice" role="status">
                <span>{notice || message}</span>
                <Button
                  tooltip={"Dismiss this status message."}
                  aria-label="Dismiss message"
                  onClick={() => {
                    notices.current.clear();
                    setMessage("");
                  }}
                >
                  <X size={16} />
                </Button>
              </div>
            )}
            <div className="below-editor">
              <Button
                tooltip={
                  echoing
                    ? "Stop the synthesized read-back."
                    : "Read the selected words or entry using a local synthesized voice. Use Play to hear your original recording."
                }
                onClick={echo}
                disabled={!entry?.text || recording}
              >
                {echoing ? <Pause size={15} /> : <Volume2 size={15} />}{" "}
                {echoing ? "Stop reading" : "Read it back"}
              </Button>
              <Button
                tooltip={
                  showRecordings
                    ? "Hide the list of original recordings."
                    : "Show original recordings, downloads, and failed-transcription retry."
                }
                onClick={() => setShowRecordings((value) => !value)}
                aria-expanded={showRecordings}
                aria-controls="original-recordings"
              >
                <Headphones size={15} /> Recordings{" "}
                {clips.length > 0 && (
                  <span className="count-pill">{clips.length}</span>
                )}
                <ChevronDown
                  size={13}
                  className={`recordings-chevron ${showRecordings ? "is-open" : ""}`}
                  aria-hidden="true"
                />
              </Button>
            </div>
            {commands && modelReady.current && discoveryContext && (
              <CommandGuide
                commands={commonCommands}
                onExplore={() => setDialog("help")}
              />
            )}
            {showRecordings && (
              <section className="recordings" id="original-recordings">
                <div className="recordings-heading">
                  <h2>The original recordings</h2>
                  <small>Kept separately from text edits</small>
                </div>
                {!clips.length && (
                  <p>
                    Audio you record will appear here, including audio that
                    needs transcription retried. Play in the editor follows your
                    edits; these files are the original source recordings.
                  </p>
                )}
                {clips.map((clip, index) => {
                  const current =
                    clipProgress?.id === clip.id ? clipProgress : undefined;
                  const duration =
                    current?.duration ??
                    Math.max(
                      0,
                      Number.isFinite(clip.duration) ? clip.duration : 0,
                    );
                  const elapsed = current?.position ?? 0;
                  return (
                    <div className="clip" key={clip.id}>
                      <Button
                        tooltip={
                          playingClip === clip.id
                            ? "Pause this original recording."
                            : `Play original recording ${index + 1}.`
                        }
                        className="clip-play"
                        disabled={recording}
                        onClick={() => playClip(clip)}
                        aria-label={`${playingClip === clip.id ? "Pause" : "Play"} recording ${index + 1}`}
                      >
                        {playingClip === clip.id ? (
                          <Pause size={16} />
                        ) : (
                          <Play size={16} />
                        )}
                      </Button>
                      <div>
                        <strong>
                          Passage {String(index + 1).padStart(2, "0")}
                        </strong>
                        <span>
                          {formatTime(clip.duration)} ·{" "}
                          {clip.transcribed
                            ? clip.transcript || "No speech detected"
                            : "Audio saved · transcription pending"}
                        </span>
                      </div>
                      {!clip.transcribed && (
                        <Button
                          tooltip={
                            "Try transcribing this saved recording again without recording it a second time."
                          }
                          disabled={busy}
                          onClick={async () => {
                            try {
                              enqueue(
                                await decodeAudio(clip.audio),
                                clip.entryId,
                                clip,
                              );
                            } catch (cause) {
                              showError(cause);
                            }
                          }}
                        >
                          Retry
                        </Button>
                      )}
                      <Button
                        tooltip={`Download original recording ${index + 1} as an audio file.`}
                        className="icon-button"
                        aria-label={`Download recording ${index + 1}`}
                        onClick={() =>
                          downloadBlob(clip.audio, `lingual-${clip.id}.wav`)
                        }
                      >
                        <ArrowDownToLine size={16} />
                      </Button>
                      <div className="clip-progress-row">
                        <progress
                          className="clip-progress"
                          aria-label={`Recording ${index + 1} playback progress`}
                          aria-valuetext={`${formatTime(elapsed)} of ${formatTime(duration)}`}
                          value={elapsed}
                          max={duration || 1}
                        />
                        <span
                          className="clip-elapsed"
                          aria-label={`Recording ${index + 1} elapsed time`}
                        >
                          {formatTime(elapsed)} / {formatTime(duration)}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </section>
            )}
          </section>
          <aside className="guide">
            <div className="guide-flower" aria-hidden="true">
              ✳
            </div>
            <p className="guide-eyebrow">A SMALL INVITATION</p>
            <h2>
              You don’t have to
              <br />
              have it all
              <br />
              <em>figured out.</em>
            </h2>
            <p>
              An idea, a wandering thought,
              <br />
              the start of something.
              <br />
              Give it a little space.
            </p>
            <div className="guide-rule" />
            <div className="guide-section-heading">
              <Sparkles size={16} />
              <h3>Let your voice do more</h3>
            </div>
            <p className="guide-description">
              Turn on voice actions, then say
              <br />
              one of these on its own.
            </p>
            <div className="command-examples">
              {commandExamples.slice(0, 4).map((text) => (
                <span key={text}>“{text}”</span>
              ))}
            </div>
            <Button
              tooltip={"Open the full list of available voice actions."}
              className="text-link"
              onClick={() => setDialog("help")}
            >
              Explore voice actions <span>↗</span>
            </Button>
            <div className="privacy-card">
              <ShieldCheck size={21} />
              <strong>Your thoughts belong to you.</strong>
              <p>
                Transcription happens right here on your device. Your audio
                never leaves this browser.
              </p>
            </div>
          </aside>
        </div>
      </main>
      {dialog && (
        <div className="modal-backdrop" onClick={() => setDialog(null)}>
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="dialog-title"
            onClick={(event) => event.stopPropagation()}
          >
            <Button
              tooltip={"Close this dialog and return to your entry."}
              className="modal-close icon-button"
              onClick={() => setDialog(null)}
              aria-label="Close dialog"
            >
              <X size={20} />
            </Button>
            {dialog === "help" ? (
              <>
                <div className="modal-icon">
                  <AudioLines size={25} />
                </div>
                <h2 id="dialog-title">Help</h2>
                <p>
                  Lingual is a place to capture speech as text and audio, then
                  shape your thoughts.
                </p>
                <ol>
                  <li>
                    <strong>Enable voice.</strong> Load speech recognition and
                    allow the microphone. Lingual starts listening and shows
                    what it hears without saving speech to the selected entry.
                    About 109 MB of speech files are cached when available.
                  </li>
                  <li>
                    <strong>Start entry.</strong> Say it or use the button to
                    create a new entry and record. Resume entry adds to the
                    selected entry. Stop entry returns to listening only; Stop
                    listening turns the microphone off.
                  </li>
                  <li>
                    <strong>Make it yours.</strong> Select text to copy, cut or
                    replace it by speaking. Undo and redo restore both words and
                    their recordings.
                  </li>
                </ol>
                <h3>Say it, then pause.</h3>
                <p>
                  With voice actions enabled, these exact phrases act as
                  commands. Turn voice actions off when you want to dictate
                  those phrases.
                </p>
                <div className="help-commands">
                  {commandExamples.map((command) => (
                    <code key={command}>{command}</code>
                  ))}
                </div>
                <p className="muted">
                  Also: “Create entry”, “Delete entry” (asks first), “Export
                  text”, and “Reveal actions”. Voice actions are on by default.
                </p>
                <h3>All {commandCatalog.length} native actions</h3>
                <details className="mode-guide">
                  <summary>How Lingual’s modes work</summary>
                  {nativeHelp.modes.map((mode) => (
                    <p key={mode.title}>
                      <strong>{mode.title}.</strong> {mode.body}
                    </p>
                  ))}
                </details>
                <input
                  className="command-search"
                  aria-label="Find a voice action"
                  placeholder="Find an action…"
                  value={commandSearch}
                  onChange={(event) => setCommandSearch(event.target.value)}
                />
                <div className="command-palette">
                  {commandCatalog
                    .filter((command) =>
                      command.label.includes(commandSearch.toLowerCase()),
                    )
                    .map((command) => (
                      <Button
                        tooltip={nativeHelp.descriptions[command.id]}
                        key={command.id}
                        onClick={() => {
                          setDialog(null);
                          dispatchCommand(command.id);
                        }}
                      >
                        {command.label}
                        <span>↗</span>
                      </Button>
                    ))}
                </div>
                <h3>Listen again</h3>
                <Button
                  disabled={busy}
                  tooltip="Load the original spoken welcome entry and its two recordings (31 MB)."
                  onClick={async () => {
                    setWelcomeLoading(true);
                    try {
                      const id = await openWelcome();
                      const items = await storage.loadEntries();
                      entriesRef.current = items;
                      setEntries(items);
                      activeIdRef.current = id;
                      setActiveId(id);
                      setDialog(null);
                      setShowTimeline(true);
                    } catch (cause) {
                      showError(cause);
                    } finally {
                      setWelcomeLoading(false);
                    }
                  }}
                >
                  Open original welcome entry
                </Button>
                <p>
                  “Read it back” uses your device’s speech voice. Play follows
                  your edited word sequence. Cut, paste, delete, undo, and
                  selection speed changes apply to text and linked audio
                  together. Entry text and replacement drafts come from speech.
                  Original recordings remain available for recovery.
                </p>
              </>
            ) : dialog === "settings" ? (
              <>
                <div className="modal-icon">
                  <Settings2 size={24} />
                </div>
                <h2 id="dialog-title">Settings</h2>
                <HeadphoneReminder message={headphoneMessage} />
                <label className="settings-row">
                  <span>
                    <strong>Voice actions</strong>
                    <small>
                      Speak commands to edit and navigate. Turn off to record
                      command phrases as ordinary entry text.
                    </small>
                  </span>
                  <input
                    type="checkbox"
                    checked={commands}
                    onChange={(event) => {
                      setCommandPreview(undefined);
                      commandsRef.current = event.target.checked;
                      setCommands(event.target.checked);
                    }}
                  />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Playback speed</strong>
                    <small>
                      Change how fast original recordings and synthesized
                      read-back play.
                    </small>
                  </span>
                  <select
                    aria-label="Playback speed"
                    value={preferences.playbackRate}
                    onChange={(event) =>
                      updatePreferences({
                        ...preferences,
                        playbackRate: Number(event.target.value),
                        echoRate: Number(event.target.value),
                      })
                    }
                  >
                    {[0.75, 1, 1.25, 1.5, 2].map((value) => (
                      <option key={value} value={value}>
                        {value}×
                      </option>
                    ))}
                  </select>
                </label>
                {booleanSettings.map(({ key, label, description }) => (
                  <label className="settings-row" key={key}>
                    <span>
                      <strong>{label}</strong>
                      <small id={`setting-${key}-description`}>
                        {description}
                      </small>
                    </span>
                    <input
                      type="checkbox"
                      aria-label={label}
                      aria-describedby={`setting-${key}-description`}
                      checked={Boolean(preferences[key])}
                      onChange={(event) =>
                        updatePreferences({
                          ...preferences,
                          [key]: event.target.checked,
                        })
                      }
                    />
                  </label>
                ))}
                <label className="settings-row">
                  <span>
                    <strong>App volume</strong>
                    <small>
                      Set Lingual’s playback loudness without changing your
                      device’s volume.
                    </small>
                  </span>
                  <input
                    aria-label="App volume"
                    type="range"
                    min="0.1"
                    max="1"
                    step="0.1"
                    value={preferences.volume}
                    onChange={(event) =>
                      updatePreferences({
                        ...preferences,
                        volume: Number(event.target.value),
                      })
                    }
                  />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Local read-back voice</strong>
                    <small>
                      Choose an installed voice for synthesized read-back. Your
                      original recorded voice is unchanged.
                    </small>
                  </span>
                  <select
                    aria-label="Read-back voice"
                    value={preferences.voiceURI}
                    onChange={(event) =>
                      updatePreferences({
                        ...preferences,
                        voiceURI: event.target.value,
                      })
                    }
                  >
                    <option value="">System default</option>
                    {localVoices.map((voice) => (
                      <option key={voice.voiceURI} value={voice.voiceURI}>
                        {voice.name}
                      </option>
                    ))}
                  </select>
                </label>

                <div className="backup-actions">
                  <Button
                    tooltip={
                      "Download all entries, edit history, and original audio as a backup."
                    }
                    disabled={busy}
                    onClick={async () => {
                      try {
                        await writes.current;
                        downloadBlob(
                          await exportBackup(),
                          "lingual-backup.lingual.json",
                        );
                      } catch (cause) {
                        showError(cause);
                      }
                    }}
                  >
                    <ArrowDownToLine size={15} /> Back up entries and audio
                  </Button>
                  <Button
                    tooltip={
                      "Add entries from a Lingual backup containing their original recordings."
                    }
                    disabled={busy}
                    onClick={() => backupUpload.current?.click()}
                  >
                    <ArrowUpFromLine size={15} /> Restore a backup
                  </Button>
                  <input
                    type="file"
                    ref={backupUpload}
                    hidden
                    accept=".json"
                    onChange={async (event) => {
                      const file = event.target.files?.[0];
                      event.target.value = "";
                      if (!file) return;
                      try {
                        if (file.size > 256 * 1024 * 1024)
                          throw new Error(
                            "Choose a backup smaller than 256 MB.",
                          );
                        await importBackup(JSON.parse(await file.text()));
                        const restored = await storage.loadEntries();
                        entriesRef.current = restored;
                        setEntries(restored);
                        setMessage(
                          "Backup restored as additional entries. Existing entries were preserved.",
                        );
                        setDialog(null);
                      } catch (cause) {
                        showError(cause);
                      }
                    }}
                  />
                </div>
                <div className="settings-info">
                  <ShieldCheck size={21} />
                  <div>
                    <strong>Local by design</strong>
                    <p>
                      Vosk previews speech locally; Whisper finalizes the
                      transcript. The first use downloads public model files. No
                      API key, paid transcription service, or speech server is
                      used.
                    </p>
                    <p>
                      Entries and original audio live in this browser’s storage.
                      Clearing site data removes them. Download important text
                      and recordings before clearing storage or switching
                      devices.
                    </p>
                    <p>
                      This first version transcribes English. Keep this tab
                      visible while recording; switching away pauses listening
                      safely.
                    </p>
                  </div>
                </div>
              </>
            ) : dialog === "export" ? (
              <>
                <div className="modal-icon">
                  <ArrowDownToLine size={23} />
                </div>
                <h2 id="dialog-title">Take your thoughts with you</h2>
                <p>
                  Export the selected passage or entry as editable text or as
                  its edited audio timeline.
                </p>
                <div className="modal-actions">
                  <Button
                    tooltip={
                      "Download the selected passage or entry as a text file."
                    }
                    onClick={() => {
                      void exportPassage(
                        "text",
                        exportRange.current ?? {
                          start: 0,
                          end: entry?.text.length ?? 0,
                        },
                      ).catch(showError);
                      setDialog(null);
                    }}
                  >
                    Export text
                  </Button>
                  <Button
                    tooltip={
                      "Download the selected passage or entry as an edited WAV recording."
                    }
                    onClick={() => {
                      void exportPassage(
                        "audio",
                        exportRange.current ?? {
                          start: 0,
                          end: entry?.text.length ?? 0,
                        },
                      ).catch(showError);
                      setDialog(null);
                    }}
                  >
                    Export audio
                  </Button>
                </div>
              </>
            ) : (
              <>
                <div className="modal-icon">
                  <Trash2 size={23} />
                </div>
                <h2 id="dialog-title">Delete this entry?</h2>
                <p>
                  “{entry ? entryTitle(entry) : ""}” and its original recordings
                  will be removed from this browser.
                </p>
                <div className="modal-actions">
                  <Button
                    tooltip={
                      "Cancel deletion and keep the entry and its recordings."
                    }
                    onClick={() => setDialog(null)}
                  >
                    Keep entry
                  </Button>
                  <Button
                    tooltip={
                      "Delete this entry and its recordings from this browser."
                    }
                    className="danger-button"
                    disabled={busy && !commandListening}
                    onClick={async () => {
                      try {
                        await confirmDelete();
                      } catch (cause) {
                        showError(cause);
                      }
                    }}
                  >
                    Delete entry
                  </Button>
                </div>
              </>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
