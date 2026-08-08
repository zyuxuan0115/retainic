//
//  Statistics aggregation and charts.
//  Retainic Web
//

import { el, clear, svgEl } from "../dom.js";
import * as i18n from "../i18n.js";
import { t, tn, tf } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as G from "../glossary.js";
import { authState } from "../auth.js";
import { navBar, spinner, emptyState, errorState, icon } from "../ui.js";

export async function StatsScreen(content) {
  content.appendChild(navBar(t("Statistics"), {}));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  let words = [];
  let entries = [];
  let dailyStats = [];
  try {
    const lists = await Repo.fetchLists(authState.uid);
    for (const l of lists) words = words.concat(await Repo.fetchWords(authState.uid, l.id));
    // Glossary practice writes the same daily tallies as list practice, so the
    // totals and today's counts have to include glossary terms as well.
    const glossaries = await Repo.fetchGlossaries(authState.uid);
    for (const g of glossaries) entries = entries.concat(await Repo.fetchEntries(authState.uid, g.id));
    dailyStats = await Repo.fetchDailyStats(authState.uid, 7).catch(() => []);
  } catch (e) { clear(body); body.appendChild(errorState(e)); return; }

  clear(body);
  if (words.length + entries.length === 0) {
    body.appendChild(emptyState(icon("bar_chart", 46), t("No Stats Yet"),
      t("Add words and practice them. Once you've memorized some, your progress shows up here.")));
    return;
  }

  // Aggregate stats (LearningStats). A word counts as memorized only once it is
  // fully remembered: 8× word, 10× translation, 7× pronunciation (remember_final);
  // a glossary term once the term and each of its definitions have had their
  // five recalls.
  const totalWords = words.length + entries.length;
  const totalMemorized = words.filter(M.isRemembered).length + entries.filter(G.isRemembered).length;
  const dates = [...words, ...entries].map((w) => w.createdAt).filter(Boolean);
  const start = dates.length ? new Date(Math.min(...dates.map((d) => +d))) : null;
  let activeDays = 1;
  if (start) {
    const s = new Date(start); s.setHours(0, 0, 0, 0);
    const n = new Date(); n.setHours(0, 0, 0, 0);
    activeDays = Math.max(1, Math.round((n - s) / 86400000) + 1);
  }
  const perDay = totalMemorized / activeDays;
  const perWeek = perDay * 7;
  const perMonth = perDay * (365.25 / 12);

  // Today remembered (derived from words and glossary terms). A term's two
  // methods line up with a word's first two: recalling the term itself, and
  // recalling what it means.
  const today = { word: 0, translation: 0, pronunciation: 0 };
  for (const w of words) {
    if (M.isToday(w.lastWordRemembered)) today.word += 1;
    if (M.isToday(w.lastTranslationRemembered)) today.translation += 1;
    if (M.isToday(w.lastPronounciationRemembered)) today.pronunciation += 1;
  }
  for (const e of entries) {
    if (M.isToday(e.lastTermRemembered)) today.word += 1;
    // Every definition is a card of its own, so each one recalled today counts
    // — the same way the daily tallies were written during practice.
    today.translation += G.definitions(e).filter((d) => M.isToday(d.lastRemembered)).length;
  }

  // Glossary progress, for the charts glossaries get to themselves. A term is
  // memorized once its term side and every one of its definitions have had
  // their five recalls; anything with at least one recall behind it is under
  // way, and the rest hasn't been started.
  const glossaryToday = { term: 0, definition: 0 };
  const glossaryProgress = { memorized: 0, started: 0, untouched: 0 };
  for (const e of entries) {
    if (M.isToday(e.lastTermRemembered)) glossaryToday.term += 1;
    const defs = G.definitions(e);
    glossaryToday.definition += defs.filter((d) => M.isToday(d.lastRemembered)).length;
    const recalls = (e.timesTermCorrect ?? 0) + defs.reduce((sum, d) => sum + d.timesCorrect, 0);
    if (G.isRemembered(e)) glossaryProgress.memorized += 1;
    else if (recalls > 0) glossaryProgress.started += 1;
    else glossaryProgress.untouched += 1;
  }

  // The glossary curve reads the fields glossary practice tallies for itself.
  const glossaryKeys = ["glossaryTerm", "glossaryDefinition"];
  const glossaryLabel = (k) => (k === "glossaryTerm" ? t("Term") : t("Definition"));
  const glossaryColors = { glossaryTerm: "#2f6bff", glossaryDefinition: "#1fb56a" };
  const glossaryWeekToday = {
    glossaryTerm: glossaryToday.term,
    glossaryDefinition: glossaryToday.definition,
  };

  const aspectKeys = ["word", "translation", "pronunciation"];
  const aspectLabel = (k) => k === "word" ? t("Word") : k === "translation" ? t("Translation") : t("Pronunciation");
  const colors = { word: "#2f6bff", translation: "#1fb56a", pronunciation: "#ff8a1f" };

  body.appendChild(el(".stats", {},
    // total card
    el(".stat-total", {},
      el(".big-icon", {}, icon("psychology", 44)),
      el(".stat-number", {}, `${totalMemorized}`),
      el(".stat-caption", {}, t("words and terms memorized")),
      el(".stat-subcaption", {}, tf("out of %lld total", totalWords)),
    ),
    el(".stat-block", {},
      el("h3", {}, t("Words today")),
      barChart(aspectKeys.map((k) => ({ label: aspectLabel(k), value: today[k], color: colors[k] }))),
    ),
    el(".stat-block", {},
      el("h3", {}, t("Words this week")),
      weekChart(dailyStats, today, aspectKeys, aspectLabel, colors),
    ),
    // Glossaries get their own two charts: how far the terms have come, and
    // what was practised today. Only shown once there are terms to chart.
    entries.length ? el(".stat-block", {},
      el("h3", {}, t("Glossary terms")),
      barChart([
        { label: t("Memorized"), value: glossaryProgress.memorized, color: colors.word },
        { label: t("In progress"), value: glossaryProgress.started, color: colors.translation },
        { label: t("Not started"), value: glossaryProgress.untouched, color: colors.pronunciation },
      ]),
      el("p.caption.center", {}, tf("%lld of %lld terms memorized", glossaryProgress.memorized, entries.length)),
    ) : null,
    entries.length ? el(".stat-block", {},
      el("h3", {}, t("Glossary practice today")),
      barChart([
        { label: t("Term"), value: glossaryToday.term, color: colors.word },
        { label: t("Definition"), value: glossaryToday.definition, color: colors.translation },
      ]),
      el("p.caption.center", {}, tn("%lld cards practised", glossaryToday.term + glossaryToday.definition)),
    ) : null,
    // The glossary week is drawn from tallies glossary practice writes for
    // itself, so it only fills in from the day that started — today always
    // comes from the terms themselves, as it does in the combined chart.
    entries.length ? el(".stat-block", {},
      el("h3", {}, t("Glossary this week")),
      weekChart(dailyStats, glossaryWeekToday, glossaryKeys, glossaryLabel, glossaryColors),
    ) : null,
    el(".stat-block", {},
      el("h3", {}, t("Average pace")),
      el(".pace-row", {},
        paceCard(t("Per day"), perDay),
        paceCard(t("Per week"), perWeek),
        paceCard(t("Per month"), perMonth),
      ),
    ),
    start ? el("p.caption.center", {},
      tf("Based on %lld days of learning since %@.", activeDays, start.toLocaleDateString(i18n.preferredLanguage()))) : null,
  ));

  function paceCard(title, value) {
    const text = value < 10 ? value.toFixed(1) : `${Math.round(value)}`;
    return el(".pace-card", {}, el(".pace-value", {}, text), el(".pace-title", {}, title));
  }
}

function barChart(bars) {
  const W = 320, H = 200, pad = 28;
  const max = Math.max(1, ...bars.map((b) => b.value));
  const bw = (W - pad * 2) / bars.length;
  const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart", preserveAspectRatio: "xMidYMid meet" });
  bars.forEach((b, i) => {
    const h = (b.value / max) * (H - pad * 2);
    const x = pad + i * bw + bw * 0.2;
    const w = bw * 0.6;
    const y = H - pad - h;
    svg.appendChild(svgEl("rect", { x, y, width: w, height: h, rx: 6, fill: b.color }));
    svg.appendChild(svgEl("text", { x: x + w / 2, y: y - 6, "text-anchor": "middle", class: "chart-val" }, document.createTextNode(`${b.value}`)));
    const label = svgEl("text", { x: x + w / 2, y: H - 8, "text-anchor": "middle", class: "chart-lbl" });
    label.appendChild(document.createTextNode(b.label));
    svg.appendChild(label);
  });
  return svg;
}

function weekChart(dailyStats, today, aspectKeys, aspectLabel, colors) {
  const W = 340, H = 220, padX = 24, padY = 28;
  const byDate = {};
  for (const s of dailyStats) byDate[s.date] = s;
  const days = [];
  const now = new Date(); now.setHours(0, 0, 0, 0);
  for (let off = 6; off >= 0; off--) {
    const d = new Date(now); d.setDate(d.getDate() - off);
    const key = Repo.dayKey(d);
    const stat = byDate[key];
    const vals = {};
    for (const k of aspectKeys) {
      vals[k] = off === 0 ? (today[k] || 0) : (stat ? (stat[k] || 0) : 0);
    }
    days.push({ date: d, vals });
  }
  const max = Math.max(1, ...days.flatMap((d) => aspectKeys.map((k) => d.vals[k])));
  const innerW = W - padX * 2, innerH = H - padY * 2;
  const x = (i) => padX + (i / 6) * innerW;
  const y = (v) => padY + innerH - (v / max) * innerH;
  const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart", preserveAspectRatio: "xMidYMid meet" });
  // gridlines + weekday labels
  days.forEach((d, i) => {
    svg.appendChild(svgEl("line", { x1: x(i), y1: padY, x2: x(i), y2: padY + innerH, stroke: "#e6e6ec", "stroke-width": 1, "stroke-dasharray": "4 4" }));
    const lbl = svgEl("text", { x: x(i), y: H - 8, "text-anchor": "middle", class: "chart-lbl" });
    lbl.appendChild(document.createTextNode(d.date.toLocaleDateString(i18n.preferredLanguage(), { weekday: "narrow" })));
    svg.appendChild(lbl);
  });
  for (const k of aspectKeys) {
    const pts = days.map((d, i) => `${x(i)},${y(d.vals[k])}`).join(" ");
    svg.appendChild(svgEl("polyline", { points: pts, fill: "none", stroke: colors[k], "stroke-width": 2.5, "stroke-linejoin": "round", "stroke-linecap": "round" }));
    days.forEach((d, i) => svg.appendChild(svgEl("circle", { cx: x(i), cy: y(d.vals[k]), r: 3, fill: colors[k] })));
  }
  // legend
  const legend = el(".chart-legend", {}, ...aspectKeys.map((k) =>
    el(".legend-item", {}, el(".legend-dot", { style: `background:${colors[k]}` }), aspectLabel(k))));
  return el(".chart-wrap", {}, svg, legend);
}
