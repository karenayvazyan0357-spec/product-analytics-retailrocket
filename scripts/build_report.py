"""Автоматическая сборка Excel-отчёта по продуктовым метрикам Retail Rocket.

Запуск из корня проекта:
    python scripts/build_report.py

Читает готовые вью из Postgres (v_funnel, v_daily, v_segments) и собирает
xlsx-файл с формулами и графиками в папку reports/.
"""
import os
from datetime import date

import pandas as pd
from sqlalchemy import create_engine

# Адрес БД можно переопределить переменной окружения DB_URL
DB_URL = os.getenv(
    "DB_URL", "postgresql+psycopg2://karenajvazan@localhost:5432/retailrocket"
)
OUT_DIR = "reports"
DOW_NAMES = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]


def load_data(engine):
    """Забирает метрики из вью. Вся логика расчёта остаётся в SQL."""
    funnel = pd.read_sql("SELECT step, visitors FROM v_funnel ORDER BY step_no", engine)
    daily = pd.read_sql(
        "SELECT day, visitors, carters, buyers, conv_pct FROM v_daily ORDER BY day",
        engine,
    )
    segments = pd.read_sql(
        "SELECT segment, buyers, orders FROM v_segments ORDER BY segment", engine
    )
    daily["day"] = pd.to_datetime(daily["day"])
    return funnel, daily, segments


def make_dow_table(daily):
    """Конверсия по дням недели: сумма покупателей / сумма посетителей."""
    t = (
        daily.assign(dow_no=daily["day"].dt.dayofweek)
        .groupby("dow_no")[["visitors", "buyers"]]
        .sum()
    )
    t["conv"] = t["buyers"] / t["visitors"]
    t.index = [DOW_NAMES[i] for i in t.index]
    t.index.name = "День недели"
    return t.reset_index()


def build_report(funnel, daily, segments, path):
    dow = make_dow_table(daily)

    with pd.ExcelWriter(path, engine="xlsxwriter", datetime_format="dd.mm.yyyy") as xw:
        wb = xw.book
        head = wb.add_format(
            {"bold": True, "bg_color": "#1F4E78", "font_color": "white",
             "border": 1, "text_wrap": True, "valign": "vcenter"}
        )
        pct = wb.add_format({"num_format": "0.00%"})
        num = wb.add_format({"num_format": "#,##0"})
        title = wb.add_format({"bold": True, "font_size": 14})

        # Сводка создаётся первой, чтобы быть первым листом
        summary = wb.add_worksheet("Сводка")

        # --- Воронка: формулы конверсий считает сам Excel ---
        funnel.to_excel(xw, sheet_name="Воронка", index=False)
        ws = xw.sheets["Воронка"]
        n = len(funnel)
        for col, name in enumerate(
            ["Шаг", "Посетители", "Конверсия от предыдущего шага", "Конверсия от первого шага"]
        ):
            ws.write(0, col, name, head)
        for r in range(2, n + 2):  # номера строк Excel (1-я строка - заголовок)
            if r > 2:
                ws.write_formula(f"C{r}", f"=B{r}/B{r-1}", pct)
            ws.write_formula(f"D{r}", f"=B{r}/$B$2", pct)
        ws.set_column("A:A", 18)
        ws.set_column("B:B", 14, num)
        ws.set_column("C:D", 22, pct)
        ws.set_row(0, 32)

        # --- Динамика по дням + график ---
        daily.to_excel(xw, sheet_name="Динамика", index=False)
        ws = xw.sheets["Динамика"]
        for col, name in enumerate(["День", "Посетители", "Добавили в корзину", "Покупатели", "Конверсия, %"]):
            ws.write(0, col, name, head)
        ws.set_column("A:A", 12)
        ws.set_column("B:E", 16)
        ws.freeze_panes(1, 0)
        m = len(daily)
        chart = wb.add_chart({"type": "line"})
        chart.add_series({
            "name": "Посетители",
            "categories": ["Динамика", 1, 0, m, 0],
            "values": ["Динамика", 1, 1, m, 1],
        })
        chart.set_title({"name": "Посетители по дням"})
        chart.set_x_axis({"date_axis": True, "num_format": "dd.mm"})
        chart.set_legend({"none": True})
        chart.set_size({"width": 760, "height": 320})
        ws.insert_chart("G2", chart)

        # --- Сегменты покупателей: доли тоже формулами ---
        segments.to_excel(xw, sheet_name="Сегменты", index=False)
        ws = xw.sheets["Сегменты"]
        k = len(segments)
        for col, name in enumerate(["Сегмент", "Покупатели", "Заказы", "Доля покупателей", "Доля заказов"]):
            ws.write(0, col, name, head)
        for r in range(2, k + 2):
            ws.write_formula(f"D{r}", f"=B{r}/SUM($B$2:$B${k+1})", pct)
            ws.write_formula(f"E{r}", f"=C{r}/SUM($C$2:$C${k+1})", pct)
        ws.set_column("A:A", 18)
        ws.set_column("B:C", 14, num)
        ws.set_column("D:E", 18, pct)
        ws.set_row(0, 32)

        # --- Дни недели + график ---
        dow.to_excel(xw, sheet_name="Дни недели", index=False)
        ws = xw.sheets["Дни недели"]
        for col, name in enumerate(["День недели", "Посетители", "Покупатели", "Конверсия"]):
            ws.write(0, col, name, head)
        for r in range(2, len(dow) + 2):
            ws.write_formula(f"D{r}", f"=C{r}/B{r}", pct)
        ws.set_column("A:A", 14)
        ws.set_column("B:C", 14, num)
        ws.set_column("D:D", 12, pct)
        chart = wb.add_chart({"type": "column"})
        chart.add_series({
            "name": "Конверсия",
            "categories": ["Дни недели", 1, 0, len(dow), 0],
            "values": ["Дни недели", 1, 3, len(dow), 3],
        })
        chart.set_title({"name": "Конверсия в покупку по дням недели"})
        chart.set_y_axis({"num_format": "0.0%"})
        chart.set_legend({"none": True})
        ws.insert_chart("F2", chart)

        # --- Сводка: ключевые показатели ссылаются на другие листы ---
        summary.write("A1", "Retail Rocket: ключевые метрики", title)
        summary.write("A3", "Период данных (полные дни)")
        summary.write("B3", f"{daily['day'].min():%d.%m.%Y} - {daily['day'].max():%d.%m.%Y}")
        summary.write("A4", "Посетителей (без краулеров)")
        summary.write_formula("B4", "='Воронка'!B2", num)
        summary.write("A5", "Покупателей (строгая воронка)")
        summary.write_formula("B5", f"='Воронка'!B{n+1}", num)
        summary.write("A6", "Конверсия просмотр - покупка")
        summary.write_formula("B6", f"='Воронка'!B{n+1}/'Воронка'!B2", pct)
        summary.write("A7", "Конверсия корзина - покупка")
        summary.write_formula("B7", f"='Воронка'!C{n+1}", pct)
        summary.write("A9", f"Отчёт собран автоматически: {date.today():%d.%m.%Y}")
        summary.set_column("A:A", 36)
        summary.set_column("B:B", 24)


def main():
    engine = create_engine(DB_URL)
    funnel, daily, segments = load_data(engine)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"retailrocket_report_{date.today():%Y-%m-%d}.xlsx")
    build_report(funnel, daily, segments, path)
    print(f"Готово: {path}")


if __name__ == "__main__":
    main()
