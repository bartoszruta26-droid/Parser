/*
 * frontend/gui/parser-gui-gtk.c
 *
 * Natywny GTK3 frontend GUI dla szkieletu daemona parser-template.
 * Zastępuje parser-gui.sh (zenity/kdialog) zachowując identyczny
 * kontrakt komunikacyjny: protokół FIFO | gui | komenda | payload.
 *
 * ┌─ Budowanie ──────────────────────────────────────────────────────────┐
 * │  gcc $(pkg-config --cflags gtk+-3.0)  \                             │
 * │      -o parser-gui-gtk parser-gui-gtk.c \                           │
 * │      $(pkg-config --libs gtk+-3.0) -lpthread                        │
 * │  # lub:                                                             │
 * │  make -C frontend/gui                                               │
 * └─────────────────────────────────────────────────────────────────────┘
 *
 * Uruchomienie — tryb interaktywny:
 *   ./parser-gui-gtk
 *   DAEMON_CONFIG=/etc/parser-template/daemon.conf ./parser-gui-gtk
 *
 * Uruchomienie — tryb jednorazowy (kompatybilny z bash-wariantem):
 *   ./parser-gui-gtk --once ping
 *   ./parser-gui-gtk --once status
 *   ./parser-gui-gtk --once frontend.event --payload '{"source":"gui"}'
 *   ./parser-gui-gtk --once shutdown
 */

#include <gtk/gtk.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <pthread.h>

/* ═══════════════════════════════════════════════════════════════════════
 * 1. Stałe i typy
 * ═══════════════════════════════════════════════════════════════════════ */

#define APP_TITLE          "Parser Template — GUI"
#define DEFAULT_RUN_DIR    "/tmp/parser-template"
#define DEFAULT_TIMEOUT_S  10
#define MAX_PATH           512
#define MAX_LINE           4096

typedef struct {
    char command_fifo[MAX_PATH];
    char response_dir[MAX_PATH];
    int  timeout_s;
} Config;

/* ═══════════════════════════════════════════════════════════════════════
 * 2. Wczytywanie konfiguracji
 * ═══════════════════════════════════════════════════════════════════════ */

/* Rozwija referencje ${VAR} używając wcześniej sparsowanych kluczy */
static void expand_vars(const char *src, char *dst, size_t dstsz,
                        const char keys[][64],
                        const char vals[][MAX_PATH],
                        int nkv)
{
    size_t si = 0, di = 0;
    while (src[si] && di + 1 < dstsz) {
        if (src[si] == '$' && src[si + 1] == '{') {
            si += 2;
            char var[64] = {0};
            size_t vi = 0;
            while (src[si] && src[si] != '}' && vi + 1 < sizeof(var))
                var[vi++] = src[si++];
            if (src[si] == '}') si++;
            for (int i = 0; i < nkv; i++) {
                if (strcmp(keys[i], var) == 0) {
                    size_t vl = strlen(vals[i]);
                    if (di + vl < dstsz) { memcpy(dst + di, vals[i], vl); di += vl; }
                    break;
                }
            }
        } else {
            dst[di++] = src[si++];
        }
    }
    dst[di] = '\0';
}

static void config_load(Config *cfg)
{
    /* Wartości domyślne */
    snprintf(cfg->command_fifo, MAX_PATH, "%s/commands.fifo", DEFAULT_RUN_DIR);
    snprintf(cfg->response_dir, MAX_PATH, "%s/responses",     DEFAULT_RUN_DIR);
    cfg->timeout_s = DEFAULT_TIMEOUT_S;

    const char *path = getenv("DAEMON_CONFIG");
    if (!path || !*path) path = "/etc/parser-template/daemon.conf";

    FILE *f = fopen(path, "r");
    if (!f) f = fopen("config/daemon.conf.example", "r");
    if (!f) return;

    char keys[48][64];
    char vals[48][MAX_PATH];
    int  nkv = 0;
    char line[MAX_LINE];

    while (fgets(line, sizeof(line), f) && nkv < 48) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\0') continue;
        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';

        /* Klucz — usuń końcowe spacje */
        size_t kl = strlen(p);
        while (kl && (p[kl - 1] == ' ' || p[kl - 1] == '\t')) p[--kl] = '\0';
        strncpy(keys[nkv], p, 63); keys[nkv][63] = '\0';

        /* Wartość — usuń newline i cudzysłowy */
        char raw[MAX_PATH];
        strncpy(raw, eq + 1, MAX_PATH - 1); raw[MAX_PATH - 1] = '\0';
        raw[strcspn(raw, "\r\n")] = '\0';
        size_t rl = strlen(raw);
        if (rl >= 2
                && ((raw[0] == '"'  && raw[rl - 1] == '"')
                 || (raw[0] == '\'' && raw[rl - 1] == '\'')))
        { memmove(raw, raw + 1, rl - 2); raw[rl - 2] = '\0'; }

        expand_vars(raw, vals[nkv], MAX_PATH, keys, vals, nkv);
        nkv++;
    }
    fclose(f);

    for (int i = 0; i < nkv; i++) {
        if      (!strcmp(keys[i], "COMMAND_FIFO"))            strncpy(cfg->command_fifo, vals[i], MAX_PATH - 1);
        else if (!strcmp(keys[i], "RESPONSE_DIR"))            strncpy(cfg->response_dir, vals[i], MAX_PATH - 1);
        else if (!strcmp(keys[i], "REQUEST_TIMEOUT_SECONDS")) cfg->timeout_s = atoi(vals[i]);
    }
}

/* ═══════════════════════════════════════════════════════════════════════
 * 3. Komunikacja z daemonem  (blokująca — wywoływana z wątku roboczego)
 * ═══════════════════════════════════════════════════════════════════════ */

static char *daemon_send(const Config *cfg, const char *command, const char *payload)
{
    /* Sprawdź czy FIFO istnieje */
    struct stat st;
    if (stat(cfg->command_fifo, &st) != 0 || !S_ISFIFO(st.st_mode))
        return g_strdup_printf(
            "{\n  \"error\": \"Daemon FIFO niedostępny\",\n"
            "  \"path\": \"%s\"\n}", cfg->command_fifo);

    /* Unikalny request_id */
    static volatile gint seq = 0;
    char req_id[128];
    snprintf(req_id, sizeof(req_id), "gui-%ld-%d-%04d",
             (long)time(NULL), (int)getpid(),
             g_atomic_int_add(&seq, 1) % 10000);

    char resp_path[MAX_PATH];
    snprintf(resp_path, MAX_PATH, "%s/%s.json", cfg->response_dir, req_id);

    /* Linia protokołu: request_id|gui|command|payload\n */
    char cmd_line[MAX_LINE];
    snprintf(cmd_line, MAX_LINE, "%s|gui|%s|%s\n",
             req_id, command, (payload && *payload) ? payload : "{}");

    /* Zapis do FIFO */
    int fd = open(cfg->command_fifo, O_WRONLY | O_NONBLOCK);
    if (fd < 0)
        return g_strdup_printf(
            "{\n  \"error\": \"Nie można otworzyć FIFO\",\n"
            "  \"detail\": \"%s\"\n}", strerror(errno));

    ssize_t w = write(fd, cmd_line, strlen(cmd_line));
    close(fd);
    if (w < 0)
        return g_strdup_printf(
            "{\n  \"error\": \"Zapis do FIFO nieudany\",\n"
            "  \"detail\": \"%s\"\n}", strerror(errno));

    /* Oczekiwanie na plik odpowiedzi */
    time_t deadline = time(NULL) + cfg->timeout_s;
    while (time(NULL) < deadline) {
        if (access(resp_path, F_OK) == 0) {
            FILE *rf = fopen(resp_path, "r");
            if (rf) {
                fseek(rf, 0, SEEK_END);
                long sz = ftell(rf);
                rewind(rf);
                char *buf = g_malloc(sz + 1);
                size_t rd = fread(buf, 1, sz, rf);
                buf[rd] = '\0';
                fclose(rf);
                return buf;
            }
            break;
        }
        g_usleep(100000);   /* 100 ms */
    }
    return g_strdup_printf(
        "{\n  \"error\": \"Timeout\",\n  \"seconds\": %d\n}", cfg->timeout_s);
}

/* ═══════════════════════════════════════════════════════════════════════
 * 4. Minimalne formatowanie JSON
 * ═══════════════════════════════════════════════════════════════════════ */

static char *pretty_json(const char *src)
{
    GString  *out   = g_string_sized_new(strlen(src) * 2);
    int       depth = 0;
    gboolean  in_str = FALSE;

    for (const char *c = src; *c; c++) {
        if (in_str) {
            g_string_append_c(out, *c);
            if (*c == '\\' && *(c + 1)) g_string_append_c(out, *++c);
            else if (*c == '"')         in_str = FALSE;
            continue;
        }
        switch (*c) {
        case '"':
            in_str = TRUE;
            g_string_append_c(out, '"');
            break;
        case '{': case '[':
            g_string_append_c(out, *c);
            g_string_append_c(out, '\n');
            depth++;
            for (int i = 0; i < depth; i++) g_string_append(out, "  ");
            break;
        case '}': case ']':
            g_string_append_c(out, '\n');
            if (depth > 0) depth--;
            for (int i = 0; i < depth; i++) g_string_append(out, "  ");
            g_string_append_c(out, *c);
            break;
        case ',':
            g_string_append_c(out, ',');
            g_string_append_c(out, '\n');
            for (int i = 0; i < depth; i++) g_string_append(out, "  ");
            break;
        case ':':
            g_string_append(out, ": ");
            break;
        case ' ': case '\t': case '\n': case '\r':
            /* pomiń oryginalne białe znaki poza stringami */
            break;
        default:
            g_string_append_c(out, *c);
        }
    }
    return g_string_free(out, FALSE);   /* wywołujący zwalnia przez g_free() */
}

/* ═══════════════════════════════════════════════════════════════════════
 * 5. Asynchroniczne wysyłanie komend (wątek + GLib idle)
 * ═══════════════════════════════════════════════════════════════════════ */

typedef struct {
    Config     cfg;
    char       command[128];
    char      *payload;         /* g_strdup'd; zwalniany przez wątek */
    GtkWidget *response_view;
    GtkWidget *spinner;
    GtkWidget *statusbar;
    guint      status_ctx;
} WorkCtx;

typedef struct {
    GtkWidget *response_view;
    GtkWidget *spinner;
    GtkWidget *statusbar;
    guint      status_ctx;
    char      *response;        /* pretty JSON; zwalniany przez idle */
    char      *status_msg;      /* zwalniany przez idle */
} IdlePayload;

static gboolean idle_update_ui(gpointer data)
{
    IdlePayload *p  = data;
    gtk_spinner_stop(GTK_SPINNER(p->spinner));
    gtk_widget_hide(p->spinner);
    GtkTextBuffer *buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(p->response_view));
    gtk_text_buffer_set_text(buf, p->response, -1);
    gtk_statusbar_pop(GTK_STATUSBAR(p->statusbar),  p->status_ctx);
    gtk_statusbar_push(GTK_STATUSBAR(p->statusbar), p->status_ctx, p->status_msg);
    g_free(p->response);
    g_free(p->status_msg);
    g_free(p);
    return G_SOURCE_REMOVE;
}

static void *worker_thread(void *arg)
{
    WorkCtx *ctx    = arg;
    char    *raw    = daemon_send(&ctx->cfg, ctx->command, ctx->payload);
    char    *pretty = pretty_json(raw);
    g_free(raw);

    IdlePayload *p   = g_new(IdlePayload, 1);
    p->response_view = ctx->response_view;
    p->spinner       = ctx->spinner;
    p->statusbar     = ctx->statusbar;
    p->status_ctx    = ctx->status_ctx;
    p->response      = pretty;
    p->status_msg    = strstr(pretty, "\"error\"")
        ? g_strdup_printf("Błąd podczas: %s", ctx->command)
        : g_strdup_printf("OK — %s", ctx->command);

    g_idle_add(idle_update_ui, p);
    g_free(ctx->payload);
    g_free(ctx);
    return NULL;
}

static void dispatch(Config *cfg, const char *command, const char *payload,
                     GtkWidget *response_view, GtkWidget *spinner,
                     GtkWidget *statusbar, guint status_ctx)
{
    WorkCtx *ctx       = g_new(WorkCtx, 1);
    ctx->cfg           = *cfg;
    strncpy(ctx->command, command, sizeof(ctx->command) - 1);
    ctx->command[sizeof(ctx->command) - 1] = '\0';
    ctx->payload       = g_strdup((payload && *payload) ? payload : "{}");
    ctx->response_view = response_view;
    ctx->spinner       = spinner;
    ctx->statusbar     = statusbar;
    ctx->status_ctx    = status_ctx;

    gtk_widget_show(spinner);
    gtk_spinner_start(GTK_SPINNER(spinner));
    gtk_statusbar_pop(GTK_STATUSBAR(statusbar), status_ctx);
    char *msg = g_strdup_printf("Wysyłanie: %s …", command);
    gtk_statusbar_push(GTK_STATUSBAR(statusbar), status_ctx, msg);
    g_free(msg);

    pthread_t tid;
    pthread_create(&tid, NULL, worker_thread, ctx);
    pthread_detach(tid);
}

/* ═══════════════════════════════════════════════════════════════════════
 * 6. Dane przycisków i callbacki sygnałów
 * ═══════════════════════════════════════════════════════════════════════ */

typedef struct {
    Config    *cfg;
    char       command[128];
    GtkWidget *payload_entry;   /* NULL = komenda bez payloadu */
    GtkWidget *response_view;
    GtkWidget *spinner;
    GtkWidget *statusbar;
    guint      status_ctx;
} BtnData;

static BtnData *btn_data_new(Config *cfg, const char *cmd,
                             GtkWidget *payload_entry,
                             GtkWidget *response_view,
                             GtkWidget *spinner,
                             GtkWidget *statusbar,
                             guint status_ctx)
{
    BtnData *d       = g_new(BtnData, 1);
    d->cfg           = cfg;
    strncpy(d->command, cmd, sizeof(d->command) - 1);
    d->command[sizeof(d->command) - 1] = '\0';
    d->payload_entry = payload_entry;
    d->response_view = response_view;
    d->spinner       = spinner;
    d->statusbar     = statusbar;
    d->status_ctx    = status_ctx;
    return d;
}

static void on_btn_clicked(GtkWidget *btn, gpointer ud)
{
    (void)btn;
    BtnData    *d       = ud;
    const char *payload = d->payload_entry
                          ? gtk_entry_get_text(GTK_ENTRY(d->payload_entry))
                          : "{}";
    dispatch(d->cfg, d->command, payload,
             d->response_view, d->spinner, d->statusbar, d->status_ctx);
}

static void on_clear_clicked(GtkWidget *btn, gpointer ud)
{
    (void)btn;
    GtkTextBuffer *buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(ud));
    gtk_text_buffer_set_text(buf, "", -1);
}

/* ═══════════════════════════════════════════════════════════════════════
 * 7. CSS — styl aplikacji
 * ═══════════════════════════════════════════════════════════════════════ */

static const char APP_CSS[] =
    "window {"
    "  background: #0f172a;"
    "}"
    ".sidebar {"
    "  background: #1e293b;"
    "  border-right: 1px solid #334155;"
    "  padding: 14px 12px;"
    "}"
    ".sidebar label {"
    "  color: #64748b;"
    "  font-size: 0.75rem;"
    "  font-weight: 700;"
    "  letter-spacing: 0.12em;"
    "  text-transform: uppercase;"
    "  margin-top: 8px;"
    "  margin-bottom: 2px;"
    "}"
    ".action-btn {"
    "  background: #38bdf8;"
    "  color: #082f49;"
    "  font-weight: 700;"
    "  border-radius: 999px;"
    "  border: none;"
    "  padding: 8px 14px;"
    "  transition: background 0.15s;"
    "}"
    ".action-btn:hover { background: #7dd3fc; }"
    ".danger-btn {"
    "  background: #dc2626;"
    "  color: #fff5f5;"
    "  font-weight: 700;"
    "  border-radius: 999px;"
    "  border: none;"
    "  padding: 8px 14px;"
    "}"
    ".danger-btn:hover { background: #ef4444; }"
    ".clear-btn {"
    "  background: transparent;"
    "  color: #64748b;"
    "  border: 1px solid #334155;"
    "  border-radius: 6px;"
    "  padding: 4px 10px;"
    "  font-size: 0.82rem;"
    "}"
    ".clear-btn:hover { background: #1e293b; color: #94a3b8; }"
    ".response-view {"
    "  background: #020617;"
    "  color: #93c5fd;"
    "  font-family: Consolas, 'Cascadia Code', Monaco, monospace;"
    "  font-size: 0.91rem;"
    "  padding: 10px;"
    "}"
    "entry {"
    "  background: #0f172a;"
    "  color: #e2e8f0;"
    "  border: 1px solid #334155;"
    "  border-radius: 8px;"
    "  padding: 5px 10px;"
    "  font-family: Consolas, Monaco, monospace;"
    "  font-size: 0.87rem;"
    "}"
    "entry:focus {"
    "  border-color: #38bdf8;"
    "  box-shadow: 0 0 0 2px rgba(56,189,248,0.2);"
    "}"
    ".right-pane {"
    "  background: #0f172a;"
    "  padding: 14px;"
    "}"
    "statusbar {"
    "  background: #1e293b;"
    "  color: #64748b;"
    "  font-size: 0.78rem;"
    "  border-top: 1px solid #334155;"
    "}";

static void apply_css(void)
{
    GtkCssProvider *prov = gtk_css_provider_new();
    gtk_css_provider_load_from_data(prov, APP_CSS, -1, NULL);
    gtk_style_context_add_provider_for_screen(
        gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(prov),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(prov);
}

/* ═══════════════════════════════════════════════════════════════════════
 * 8. Budowanie interfejsu
 * ═══════════════════════════════════════════════════════════════════════ */

static GtkWidget *sidebar_btn(const char *label, const char *css_class,
                               const char *tooltip)
{
    GtkWidget *btn = gtk_button_new_with_label(label);
    gtk_widget_set_tooltip_text(btn, tooltip);
    gtk_widget_set_hexpand(btn, TRUE);
    gtk_style_context_add_class(gtk_widget_get_style_context(btn), css_class);
    return btn;
}

static GtkWidget *section_label(const char *text)
{
    GtkWidget *lbl = gtk_label_new(text);
    gtk_widget_set_halign(lbl, GTK_ALIGN_START);
    return lbl;
}

static void build_ui(Config *cfg)
{
    apply_css();

    /* ── Okno główne ── */
    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size(GTK_WINDOW(win), 900, 600);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    /* ── Pasek tytułowy ── */
    GtkWidget *hbar = gtk_header_bar_new();
    gtk_header_bar_set_title(GTK_HEADER_BAR(hbar), "Parser Template");
    gtk_header_bar_set_subtitle(GTK_HEADER_BAR(hbar), "GUI Frontend — szkielet daemona");
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hbar), TRUE);
    gtk_window_set_titlebar(GTK_WINDOW(win), hbar);

    /* Spinner w nagłówku (widoczny podczas oczekiwania na daemon) */
    GtkWidget *spinner = gtk_spinner_new();
    gtk_header_bar_pack_end(GTK_HEADER_BAR(hbar), spinner);

    /* ── Korzeń ── */
    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), root);

    GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_paned_set_position(GTK_PANED(paned), 210);
    gtk_box_pack_start(GTK_BOX(root), paned, TRUE, TRUE, 0);

    /* ══════════════════════════════════════════
     * LEWY PANEL — akcje
     * ══════════════════════════════════════════ */
    GtkWidget *sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
    gtk_style_context_add_class(gtk_widget_get_style_context(sidebar), "sidebar");
    gtk_widget_set_size_request(sidebar, 190, -1);

    /* Sekcja: System */
    gtk_box_pack_start(GTK_BOX(sidebar), section_label("System"), FALSE, FALSE, 0);

    GtkWidget *btn_ping   = sidebar_btn("⬤  Ping",   "action-btn", "Sprawdź czy daemon odpowiada (ping)");
    GtkWidget *btn_status = sidebar_btn("📋  Status", "action-btn", "Pobierz bieżący stan daemona (status)");
    gtk_box_pack_start(GTK_BOX(sidebar), btn_ping,   FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(sidebar), btn_status, FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(sidebar),
        gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 6);

    /* Sekcja: Zdarzenie */
    gtk_box_pack_start(GTK_BOX(sidebar), section_label("Zdarzenie frontend"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(sidebar), section_label("Payload JSON:"),      FALSE, FALSE, 0);

    GtkWidget *payload_entry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(payload_entry), "{\"source\":\"gui\"}");
    gtk_entry_set_placeholder_text(GTK_ENTRY(payload_entry), "{\"klucz\":\"wartość\"}");
    gtk_box_pack_start(GTK_BOX(sidebar), payload_entry, FALSE, FALSE, 0);

    GtkWidget *btn_event = sidebar_btn("📤  Wyślij zdarzenie", "action-btn",
                                       "Wyślij frontend.event do daemona");
    gtk_box_pack_start(GTK_BOX(sidebar), btn_event, FALSE, FALSE, 0);

    /* Elastyczny odstęp */
    gtk_box_pack_start(GTK_BOX(sidebar),
        gtk_box_new(GTK_ORIENTATION_VERTICAL, 0), TRUE, TRUE, 0);

    gtk_box_pack_start(GTK_BOX(sidebar),
        gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 6);

    /* Sekcja: Sterowanie */
    gtk_box_pack_start(GTK_BOX(sidebar), section_label("Sterowanie"), FALSE, FALSE, 0);

    GtkWidget *btn_shutdown = sidebar_btn("⏹  Shutdown", "danger-btn",
                                          "Wyślij polecenie zatrzymania daemona");
    gtk_box_pack_start(GTK_BOX(sidebar), btn_shutdown, FALSE, FALSE, 0);

    gtk_paned_pack1(GTK_PANED(paned), sidebar, FALSE, FALSE);

    /* ══════════════════════════════════════════
     * PRAWY PANEL — odpowiedź daemona
     * ══════════════════════════════════════════ */
    GtkWidget *right = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_style_context_add_class(gtk_widget_get_style_context(right), "right-pane");

    /* Nagłówek z przyciskiem Wyczyść */
    GtkWidget *resp_hdr = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *lbl_resp = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(lbl_resp), "<b>Odpowiedź daemona</b>");
    gtk_widget_set_halign(lbl_resp, GTK_ALIGN_START);
    GtkWidget *btn_clear = gtk_button_new_with_label("Wyczyść");
    gtk_style_context_add_class(gtk_widget_get_style_context(btn_clear), "clear-btn");
    gtk_box_pack_start(GTK_BOX(resp_hdr), lbl_resp,    TRUE,  TRUE,  0);
    gtk_box_pack_end  (GTK_BOX(resp_hdr), btn_clear,   FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(right), resp_hdr, FALSE, FALSE, 0);

    /* Scrollowany widok tekstowy */
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    GtkWidget *tv = gtk_text_view_new();
    gtk_text_view_set_editable(GTK_TEXT_VIEW(tv), FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(tv), FALSE);
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(tv), TRUE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(tv), GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(tv), 10);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(tv), 10);
    gtk_style_context_add_class(gtk_widget_get_style_context(tv), "response-view");
    GtkTextBuffer *tbuf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(tv));
    gtk_text_buffer_set_text(tbuf,
        "Brak odpowiedzi.\nWybierz akcję z panelu po lewej stronie.", -1);
    gtk_container_add(GTK_CONTAINER(scroll), tv);
    gtk_box_pack_start(GTK_BOX(right), scroll, TRUE, TRUE, 0);

    gtk_paned_pack2(GTK_PANED(paned), right, TRUE, FALSE);

    /* ── Pasek statusu ── */
    GtkWidget *sbar = gtk_statusbar_new();
    guint sctx = gtk_statusbar_get_context_id(GTK_STATUSBAR(sbar), "main");
    char sbar_init[MAX_PATH + 48];
    snprintf(sbar_init, sizeof(sbar_init),
             "Gotowy  |  FIFO: %s  |  Timeout: %ds",
             cfg->command_fifo, cfg->timeout_s);
    gtk_statusbar_push(GTK_STATUSBAR(sbar), sctx, sbar_init);
    gtk_box_pack_end(GTK_BOX(root), sbar, FALSE, FALSE, 0);

    /* ══════════════════════════════════════════
     * Podłączenie sygnałów
     * ══════════════════════════════════════════ */
    BtnData *dp = btn_data_new(cfg, "ping",           NULL,          tv, spinner, sbar, sctx);
    BtnData *ds = btn_data_new(cfg, "status",         NULL,          tv, spinner, sbar, sctx);
    BtnData *de = btn_data_new(cfg, "frontend.event", payload_entry, tv, spinner, sbar, sctx);
    BtnData *dd = btn_data_new(cfg, "shutdown",       NULL,          tv, spinner, sbar, sctx);

    g_signal_connect(btn_ping,     "clicked", G_CALLBACK(on_btn_clicked),   dp);
    g_signal_connect(btn_status,   "clicked", G_CALLBACK(on_btn_clicked),   ds);
    g_signal_connect(btn_event,    "clicked", G_CALLBACK(on_btn_clicked),   de);
    g_signal_connect(btn_shutdown, "clicked", G_CALLBACK(on_btn_clicked),   dd);
    g_signal_connect(btn_clear,    "clicked", G_CALLBACK(on_clear_clicked), tv);

    /* Enter w polu payload → uruchom btn_event */
    g_signal_connect_swapped(payload_entry, "activate",
                             G_CALLBACK(gtk_button_clicked), btn_event);

    gtk_widget_show_all(win);
    gtk_widget_hide(spinner);   /* ukryty dopóki nie trwa żądanie */
}

/* ═══════════════════════════════════════════════════════════════════════
 * 9. Punkt wejścia
 * ═══════════════════════════════════════════════════════════════════════ */

static void print_usage(const char *prog)
{
    fprintf(stderr,
        "Użycie: %s [OPCJE]\n\n"
        "Opcje:\n"
        "  --once <komenda>   Wyślij jedną komendę, wypisz odpowiedź JSON i zakończ.\n"
        "                     Dostępne komendy: ping | status | frontend.event | shutdown\n"
        "  --payload <JSON>   Payload JSON dla --once frontend.event.\n"
        "  -h, --help         Wyświetl tę pomoc.\n\n"
        "Zmienne środowiskowe:\n"
        "  DAEMON_CONFIG      Ścieżka do pliku konfiguracji daemona.\n\n"
        "Przykłady:\n"
        "  %s\n"
        "  %s --once ping\n"
        "  %s --once frontend.event --payload '{\"source\":\"gui\"}'\n"
        "  DAEMON_CONFIG=/etc/parser-template/daemon.conf %s\n",
        prog, prog, prog, prog, prog);
}

int main(int argc, char **argv)
{
    /* Parsowanie argumentów przed gtk_init — --once działa bezgłowo */
    const char *once_command = NULL;
    const char *once_payload = "{}";

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--once")) {
            if (++i >= argc) { fprintf(stderr, "Brak wartości dla --once\n"); return 64; }
            once_command = argv[i];
        } else if (!strcmp(argv[i], "--payload")) {
            if (++i >= argc) { fprintf(stderr, "Brak wartości dla --payload\n"); return 64; }
            once_payload = argv[i];
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            print_usage(argv[0]);
            return 0;
        }
    }

    Config cfg;
    config_load(&cfg);

    /* ── Tryb jednorazowy (bezgłowy, bez GTK) ── */
    if (once_command) {
        const char *valid[] = { "ping", "status", "frontend.event", "shutdown", NULL };
        int ok = 0;
        for (int i = 0; valid[i]; i++)
            if (!strcmp(once_command, valid[i])) { ok = 1; break; }
        if (!ok) {
            fprintf(stderr, "Nieobsługiwana komenda --once: %s\n", once_command);
            return 64;
        }
        char *resp = daemon_send(&cfg, once_command, once_payload);
        puts(resp);
        g_free(resp);
        return 0;
    }

    /* ── Tryb interaktywny GTK ── */
    gtk_init(&argc, &argv);
    build_ui(&cfg);
    gtk_main();
    return 0;
}
