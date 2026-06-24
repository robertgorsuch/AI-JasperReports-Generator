package com.actian.jasper;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Paint;
import java.awt.geom.Ellipse2D;

import net.sf.jasperreports.charts.JRChart;
import net.sf.jasperreports.charts.JRChartCustomizer;

import org.jfree.chart.JFreeChart;
import org.jfree.chart.axis.CategoryLabelPositions;
import org.jfree.chart.axis.NumberAxis;
import org.jfree.chart.plot.CategoryPlot;
import org.jfree.chart.plot.DatasetRenderingOrder;
import org.jfree.chart.renderer.category.BarRenderer;
import org.jfree.chart.renderer.category.LineAndShapeRenderer;
import org.jfree.chart.renderer.category.StandardBarPainter;
import org.jfree.data.category.CategoryDataset;
import org.jfree.data.category.DefaultCategoryDataset;

/**
 * Default Actian bar-chart customizer (generic; not column-specific).
 *
 *  - Colors every bar of the FIRST series on an Actian-blue gradient scaled by
 *    its value (palest = lowest volume, deepest navy = highest), so the bar
 *    color itself encodes the measure.
 *  - If a SECOND series is present, overlays it as a trend line on a secondary
 *    range axis (the two measures usually live on different scales), with point
 *    markers + legend. The axis label is taken from the second series name.
 *
 * Series are identified by position (row 0 = bars, row 1 = trend), so it works
 * for any bar chart whose dataset feeds one or two category series. Attach via
 * the chart element's
 * customizerClass="com.actian.jasper.GradientTrendCustomizer".
 */
public class GradientTrendCustomizer implements JRChartCustomizer {

    private static final Color BLUE_LIGHT = new Color(0xB8, 0xD4, 0xEC); // pale blue (low)
    private static final Color BLUE_DEEP  = new Color(0x0A, 0x2A, 0x4A); // deep navy (high)
    private static final Color ACCENT     = new Color(0xE8, 0x77, 0x22); // amber trend line

    @Override
    public void customize(JFreeChart chart, JRChart jasperChart) {
        if (!(chart.getPlot() instanceof CategoryPlot)) {
            return;
        }
        CategoryPlot plot = (CategoryPlot) chart.getPlot();
        CategoryDataset src = plot.getDataset();
        if (src == null || src.getRowCount() == 0) {
            return;
        }

        Comparable<?> barKey = src.getRowKey(0);
        boolean hasTrend = src.getRowCount() > 1;
        Comparable<?> trendKey = hasTrend ? src.getRowKey(1) : null;

        final DefaultCategoryDataset bars = new DefaultCategoryDataset();
        final DefaultCategoryDataset line = new DefaultCategoryDataset();
        double min = Double.MAX_VALUE, max = -Double.MAX_VALUE;
        int nCols = src.getColumnCount();
        for (int c = 0; c < nCols; c++) {
            Number v = src.getValue(0, c);
            if (v != null) {
                double d = v.doubleValue();
                if (d < min) min = d;
                if (d > max) max = d;
            }
        }
        for (int c = 0; c < nCols; c++) {
            Comparable<?> col = src.getColumnKey(c);
            bars.addValue(src.getValue(0, c), barKey, col);
            if (hasTrend) {
                Number uv = src.getValue(1, c);
                if (uv != null) {
                    line.addValue(uv, trendKey, col);
                }
            }
        }

        final double fmin = min, fmax = max;

        // --- gradient blue bars (color encodes the measure) ---
        BarRenderer barRenderer = new BarRenderer() {
            @Override
            public Paint getItemPaint(int row, int column) {
                Number v = bars.getValue(row, column);
                double t = (fmax > fmin && v != null)
                        ? (v.doubleValue() - fmin) / (fmax - fmin) : 0.0;
                return blend(BLUE_LIGHT, BLUE_DEEP, t);
            }
        };
        barRenderer.setBarPainter(new StandardBarPainter()); // flat fill, no glossy sheen
        barRenderer.setShadowVisible(false);
        barRenderer.setDrawBarOutline(false);
        barRenderer.setItemMargin(0.06);
        barRenderer.setSeriesPaint(0, blend(BLUE_LIGHT, BLUE_DEEP, 0.65)); // legend swatch
        plot.setDataset(0, bars);
        plot.setRenderer(0, barRenderer);

        // --- trend line on a secondary axis ---
        if (hasTrend && line.getColumnCount() > 0) {
            NumberAxis trendAxis = new NumberAxis(String.valueOf(trendKey));
            trendAxis.setLabelPaint(ACCENT);
            trendAxis.setTickLabelPaint(ACCENT);
            trendAxis.setAutoRangeIncludesZero(true);
            plot.setRangeAxis(1, trendAxis);
            plot.setDataset(1, line);
            plot.mapDatasetToRangeAxis(1, 1);

            LineAndShapeRenderer lineRenderer = new LineAndShapeRenderer(true, true);
            lineRenderer.setSeriesPaint(0, ACCENT);
            lineRenderer.setSeriesStroke(0, new BasicStroke(2.2f));
            lineRenderer.setSeriesShape(0, new Ellipse2D.Double(-3, -3, 6, 6));
            lineRenderer.setSeriesFillPaint(0, ACCENT);
            plot.setRenderer(1, lineRenderer);
        }

        plot.setDatasetRenderingOrder(DatasetRenderingOrder.FORWARD); // bars first, line on top
        plot.getDomainAxis().setCategoryLabelPositions(CategoryLabelPositions.UP_45);
    }

    private static Color blend(Color a, Color b, double t) {
        t = Math.max(0.0, Math.min(1.0, t));
        int r = (int) Math.round(a.getRed()   + (b.getRed()   - a.getRed())   * t);
        int g = (int) Math.round(a.getGreen() + (b.getGreen() - a.getGreen()) * t);
        int bl = (int) Math.round(a.getBlue()  + (b.getBlue()  - a.getBlue())  * t);
        return new Color(r, g, bl);
    }
}
