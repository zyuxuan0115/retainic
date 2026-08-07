//
//  Trash: deleted vocabulary lists and glossaries, restore and purge.
//  Retainic Web
//

import { el, clear, toast } from "../dom.js";
import { t, tn } from "../i18n.js";
import * as Repo from "../repository.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, iconButton, spinner, emptyState, confirmDialog, icon, rectStackGlyph, errorState } from "../ui.js";

// Lists and glossaries are separate collections with the same soft-delete
// shape, so the screen renders one section per kind from a single description
// of how to count, restore, and purge each.
const KINDS = [
  {
    id: "lists",
    sectionKey: "Lists",
    glyph: () => rectStackGlyph(),
    fetch: (uid) => Repo.fetchTrashedLists(uid),
    subtitle: (list) => tn("%lld words", list.wordCount ?? 0),
    restore: (uid, list) => Repo.restoreList(uid, list.id),
    purge: (uid, list) => Repo.purgeList(uid, list.id),
  },
  {
    id: "glossaries",
    sectionKey: "Glossaries",
    glyph: () => icon("dictionary", 24),
    fetch: (uid) => Repo.fetchTrashedGlossaries(uid),
    subtitle: (glossary) => tn("%lld terms", glossary.entryCount ?? 0),
    restore: (uid, glossary) => Repo.restoreGlossary(uid, glossary.id),
    purge: (uid, glossary) => Repo.purgeGlossary(uid, glossary.id),
  },
];

export async function TrashScreen(content) {
  // Trashed items per kind, in KINDS order.
  let groups = KINDS.map((kind) => ({ kind, items: [] }));
  const emptyBtn = iconButton(icon("delete_sweep", 24), () => confirmEmptyTrash(), { label: t("Empty Trash"), danger: true });
  emptyBtn.style.display = "none";
  content.appendChild(navBar(t("Trash"), { trailing: emptyBtn }));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  const total = () => groups.reduce((sum, g) => sum + g.items.length, 0);

  function confirmEmptyTrash() {
    if (!total()) return;
    confirmDialog({
      message: `${t("Permanently delete everything in the Trash?")} ${t("This can't be undone.")}`,
      confirmLabel: t("Empty Trash"), workingLabel: t("Deleting…"), danger: true,
      // Non-interruptible: the dialog stays (and blocks) until everything is gone.
      onConfirm: async () => {
        for (const { kind, items } of groups)
          for (const item of items) await kind.purge(authState.uid, item);
        await reload();
      },
    });
  }

  async function reload() {
    try {
      groups = await Promise.all(KINDS.map(async (kind) => ({ kind, items: await kind.fetch(authState.uid) })));
    } catch (e) { clear(body); body.appendChild(errorState(e)); return; }
    emptyBtn.style.display = total() ? "" : "none";
    clear(body);
    if (total() === 0) {
      body.appendChild(emptyState(icon("delete", 46), t("Trash is Empty"),
        t("Deleted lists and glossaries are kept here until you restore or permanently delete them.")));
      return;
    }
    // With only one kind in the trash its heading would be noise; show headings
    // only when both kinds are present.
    const filled = groups.filter((g) => g.items.length);
    for (const { kind, items } of filled) {
      if (filled.length > 1) body.appendChild(el(".section-title.list-section-title", {}, t(kind.sectionKey)));
      const listEl = el(".list");
      for (const item of items) listEl.appendChild(trashRow(kind, item));
      body.appendChild(listEl);
    }
  }

  function trashRow(kind, item) {
    return el(".row", {},
      el(".row-lead", {}, kind.glyph()),
      el(".row-main", {},
        el(".row-title", {}, item.name),
        el(".row-sub", {}, kind.subtitle(item)),
      ),
      iconButton(icon("restore_from_trash", 22), async () => {
        try { await kind.restore(authState.uid, item); reload(); }
        catch (err) { toast(Auth.friendlyMessage(err)); }
      }, { label: t("Restore") }),
      iconButton(icon("delete_forever", 22), () => {
        confirmDialog({
          message: `${t("Delete Forever")} “${item.name}”? ${t("This can't be undone.")}`,
          confirmLabel: t("Delete Forever"), workingLabel: t("Deleting…"), danger: true,
          // Let errors propagate so the dialog re-enables and toasts; on success
          // the dialog closes only after the item is fully purged.
          onConfirm: async () => {
            await kind.purge(authState.uid, item);
            await reload();
          },
        });
      }, { label: t("Delete Forever"), danger: true }),
    );
  }

  reload();
}
