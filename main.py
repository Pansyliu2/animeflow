"""AnimeFlow · 精简可打包版（Flet 0.25.2）。

功能：搜索番剧元数据、查看详情、跳转原站。
说明：只展示公开元数据，不提供、不解析任何视频流地址。
"""
from __future__ import annotations

import logging
import threading

import flet as ft
import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("animeflow")

API = "https://api.jikan.moe/v4/anime"
USER_AGENT = "AnimeFlow/1.0 (Android)"


def search_anime(keyword: str, limit: int = 20) -> list[dict]:
    """调用 Jikan 搜索番剧，返回统一结构列表。"""
    log.info("搜索: %s", keyword)
    response = requests.get(
        API,
        params={"q": keyword, "limit": limit, "sfw": "true"},
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        timeout=25,
    )
    if response.status_code == 429:
        raise RuntimeError("请求太频繁，请等 5 秒再试")
    response.raise_for_status()

    items: list[dict] = []
    for entry in response.json().get("data") or []:
        image = (entry.get("images") or {}).get("jpg") or {}
        items.append(
            {
                "title": entry.get("title_english")
                or entry.get("title")
                or "未知标题",
                "cover": image.get("image_url") or "",
                "score": entry.get("score"),
                "year": entry.get("year"),
                "episodes": entry.get("episodes"),
                "status": (entry.get("status") or "").replace("Currently ", ""),
                "synopsis": (entry.get("synopsis") or "").strip(),
                "url": entry.get("url") or "",
            }
        )
    log.info("搜索完成，共 %d 条", len(items))
    return items


def meta_line(item: dict) -> str:
    """把年份 / 评分 / 话数 / 状态拼成一行。"""
    parts: list[str] = []
    if item.get("year"):
        parts.append(str(item["year"]))
    if item.get("score"):
        parts.append(f"★ {item['score']:.1f}")
    if item.get("episodes"):
        parts.append(f"{item['episodes']} 话")
    if item.get("status"):
        parts.append(item["status"])
    return " · ".join(parts) or "暂无信息"


class App:
    """界面与交互。"""

    def __init__(self, page: ft.Page) -> None:
        self.page = page
        self.busy = False
        self.items: list[dict] = []

    def mount(self) -> None:
        page = self.page
        page.title = "AnimeFlow"
        page.theme_mode = ft.ThemeMode.DARK
        page.bgcolor = "#12141c"
        page.padding = ft.padding.only(left=12, right=12, top=12, bottom=0)

        self.progress = ft.ProgressRing(
            width=16, height=16, stroke_width=2, visible=False
        )
        self.status = ft.Text("输入番剧名称开始搜索", size=11, color=ft.colors.GREY_500)
        self.field = ft.TextField(
            hint_text="例如：Frieren / 芙莉莲",
            prefix_icon=ft.icons.SEARCH,
            border_radius=22,
            filled=True,
            dense=True,
            expand=True,
            on_submit=self.on_search,
        )
        self.list_view = ft.ListView(expand=True, spacing=0)

        self.search_view = ft.Column(
            expand=True,
            spacing=8,
            controls=[
                ft.Row(
                    controls=[
                        ft.Text("AnimeFlow", size=20, weight=ft.FontWeight.BOLD),
                        ft.Container(expand=True),
                        self.progress,
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Row(
                    controls=[
                        self.field,
                        ft.IconButton(
                            icon=ft.icons.ARROW_FORWARD,
                            tooltip="搜索",
                            on_click=self.on_search,
                        ),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                self.status,
                self.list_view,
            ],
        )
        self.detail_view = ft.Column(
            expand=True,
            visible=False,
            spacing=8,
            scroll=ft.ScrollMode.AUTO,
        )

        page.add(
            ft.Column(
                controls=[self.search_view, self.detail_view],
                expand=True,
                spacing=0,
            )
        )
        page.update()
        log.info("界面初始化完成")

    def on_search(self, e: ft.ControlEvent | None = None) -> None:
        keyword = (self.field.value or "").strip()
        if not keyword:
            self.status.value = "请先输入关键词"
            self.page.update()
            return
        if self.busy:
            log.info("上一次搜索还没结束")
            return

        self.busy = True
        self.progress.visible = True
        self.status.value = f"正在搜索：{keyword}"
        self.list_view.controls.clear()
        self.page.update()

        self.run_background(self.worker, keyword)

    def worker(self, keyword: str) -> None:
        error = ""
        items: list[dict] = []
        try:
            items = search_anime(keyword)
        except requests.exceptions.Timeout:
            log.exception("搜索超时")
            error = "请求超时，请检查网络"
        except requests.exceptions.RequestException as exc:
            log.exception("网络请求失败")
            error = f"网络错误：{exc}"
        except RuntimeError as exc:
            log.exception("接口返回错误")
            error = str(exc)
        except ValueError:
            log.exception("解析失败")
            error = "数据解析失败，请稍后重试"

        self.busy = False
        self.progress.visible = False
        self.items = items
        self.list_view.controls.clear()

        if error:
            self.status.value = error
            self.list_view.controls.append(self.tip(ft.icons.ERROR_OUTLINE, error))
        elif not items:
            self.status.value = "没有找到结果"
            self.list_view.controls.append(
                self.tip(ft.icons.SEARCH_OFF, "没有找到，换个关键词试试")
            )
        else:
            self.status.value = f"共 {len(items)} 条结果"
            for item in items:
                self.list_view.controls.append(self.card(item))

        try:
            self.page.update()
        except Exception:
            log.debug("页面已关闭，跳过刷新")

    def tip(self, icon: str, text: str) -> ft.Control:
        return ft.Container(
            padding=40,
            alignment=ft.alignment.center,
            content=ft.Column(
                controls=[
                    ft.Icon(icon, size=38, color=ft.colors.GREY_600),
                    ft.Text(text, size=12, color=ft.colors.GREY_500),
                ],
                spacing=10,
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def card(self, item: dict) -> ft.Control:
        cover: ft.Control = (
            ft.Image(
                src=item["cover"],
                width=58,
                height=82,
                fit=ft.ImageFit.COVER,
                border_radius=6,
            )
            if item["cover"]
            else ft.Container(
                width=58,
                height=82,
                bgcolor="#1d2130",
                border_radius=6,
                content=ft.Icon(
                    ft.icons.IMAGE_NOT_SUPPORTED, size=18, color=ft.colors.GREY_600
                ),
            )
        )
        return ft.Container(
            padding=ft.padding.symmetric(vertical=8),
            ink=True,
            on_click=lambda e, it=item: self.show_detail(it),
            content=ft.Row(
                controls=[
                    cover,
                    ft.Column(
                        controls=[
                            ft.Text(
                                item["title"],
                                size=13,
                                weight=ft.FontWeight.W_600,
                                max_lines=2,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            ft.Text(meta_line(item), size=10, color=ft.colors.GREY_400),
                        ],
                        spacing=3,
                        expand=True,
                    ),
                    ft.Icon(ft.icons.CHEVRON_RIGHT, size=18, color=ft.colors.GREY_600),
                ],
                spacing=10,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def chip(self, text: str) -> ft.Control:
        return ft.Container(
            bgcolor="#1b2436",
            border_radius=9,
            padding=ft.padding.symmetric(horizontal=8, vertical=3),
            content=ft.Text(text, size=10, color=ft.colors.BLUE_100),
        )

    def show_detail(self, item: dict) -> None:
        chips: list[ft.Control] = []
        if item.get("score"):
            chips.append(self.chip(f"★ {item['score']:.1f}"))
        if item.get("year"):
            chips.append(self.chip(f"{item['year']} 年"))
        if item.get("episodes"):
            chips.append(self.chip(f"{item['episodes']} 话"))
        if item.get("status"):
            chips.append(self.chip(item["status"]))

        cover: ft.Control = (
            ft.Image(
                src=item["cover"],
                width=104,
                height=146,
                fit=ft.ImageFit.COVER,
                border_radius=8,
            )
            if item["cover"]
            else ft.Container(
                width=104,
                height=146,
                bgcolor="#1d2130",
                border_radius=8,
                content=ft.Icon(
                    ft.icons.IMAGE_NOT_SUPPORTED, size=24, color=ft.colors.GREY_600
                ),
            )
        )

        self.detail_view.controls = [
            ft.Row(
                controls=[
                    ft.TextButton(text="‹ 返回", on_click=self.on_back),
                    ft.Text("详情", size=16, weight=ft.FontWeight.BOLD),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            ft.Row(
                controls=[
                    cover,
                    ft.Column(
                        controls=[
                            ft.Text(item["title"], size=15, weight=ft.FontWeight.BOLD),
                            ft.Text(meta_line(item), size=10, color=ft.colors.GREY_500),
                        ],
                        spacing=6,
                        expand=True,
                    ),
                ],
                spacing=12,
                vertical_alignment=ft.CrossAxisAlignment.START,
            ),
            (
                ft.Row(controls=chips, wrap=True, spacing=6, run_spacing=6)
                if chips
                else ft.Container(height=0)
            ),
            ft.Text(
                item["synopsis"] or "该来源没有提供简介。",
                size=12,
                color=ft.colors.GREY_300,
                selectable=True,
            ),
            ft.ElevatedButton(
                text="打开 MAL 页面",
                icon=ft.icons.OPEN_IN_NEW,
                on_click=lambda e, url=item["url"]: self.open_url(url),
            ),
            ft.Container(height=24),
        ]
        self.search_view.visible = False
        self.detail_view.visible = True
        self.page.update()
        log.info("打开详情: %s", item["title"])

    def on_back(self, e: ft.ControlEvent) -> None:
        self.search_view.visible = True
        self.detail_view.visible = False
        self.page.update()

    def open_url(self, url: str) -> None:
        if not url:
            self.status.value = "该条目没有可用的链接"
            self.page.update()
            return
        try:
            self.page.launch_url(url)
        except Exception:
            log.exception("打开链接失败: %s", url)

    def run_background(self, fn, *args) -> None:
        """后台线程执行，兼容不同 Flet 版本。"""

        def wrapper() -> None:
            try:
                fn(*args)
            except Exception:
                log.exception("后台任务异常")
                self.busy = False
                self.progress.visible = False
                self.status.value = "出现异常，请重试"
                try:
                    self.page.update()
                except Exception:
                    log.debug("页面已关闭")

        run_thread = getattr(self.page, "run_thread", None)
        if callable(run_thread):
            run_thread(wrapper)
        else:
            threading.Thread(target=wrapper, daemon=True).start()


def main(page: ft.Page) -> None:
    app = App(page)
    app.mount()


if __name__ == "__main__":
    ft.app(target=main)
