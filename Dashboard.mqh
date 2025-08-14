//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include "Logger.mqh"
#include "Settings.mqh"

//+------------------------------------------------------------------+
//| Třída pro vykreslení informačního panelu do grafu                |
//+------------------------------------------------------------------+
class CDashboard
{
private:
    SSettings m_settings; // Uchováme si kopii nastavení
    CLogger m_logger;
    long    m_chart_id;
    string  m_prefix;
    string  m_sorted_symbols[];
    // Recovery info
    string  m_recovery_label_name;

    //--- Nastavení vzhledu panelu
    int     PANEL_X_POS;
    int     PANEL_Y_POS;
    int     STATUS_LABEL_Y_POS;
    int     STATUS_ROW_HEIGHT;
    int     PANEL_WIDTH;
    int     PANEL_ROW_HEIGHT;
    color   PANEL_BG_COLOR;
    color   PANEL_BORDER_COLOR;
    color   SCORE_BAR_COLOR;
    color   SCORE_BAR_BG_COLOR;
    
    //--- Pozice sloupců
    int     COL_SYMBOL_X;
    int     COL_SCORE_X;
    int     COL_RSI_X;
    int     COL_BB_X;
    int     COL_STOCH_X;
    int     COL_GRID_X;
    int     COL_FINAL_X;

public:
    CDashboard()
    {
        m_chart_id = 0; 
        m_prefix = "Dashboard_";
        PANEL_X_POS = 10;
        STATUS_LABEL_Y_POS = 10;  // OPRAVA: Posun výš (z 20 na 10)
        STATUS_ROW_HEIGHT = 32;
        PANEL_Y_POS = STATUS_LABEL_Y_POS + STATUS_ROW_HEIGHT;
        PANEL_WIDTH = 470;    // Rozšířil pro větší mezeru Grid sloupce
        PANEL_ROW_HEIGHT = 20;
        PANEL_BG_COLOR = clrWhiteSmoke;
        PANEL_BORDER_COLOR = clrGray;
        SCORE_BAR_COLOR = clrDodgerBlue;
        SCORE_BAR_BG_COLOR = clrLightGray;
        COL_SYMBOL_X = 15;
        COL_SCORE_X = 80;
        COL_RSI_X = 240;
        COL_BB_X = 280;
        COL_STOCH_X = 320;
        COL_FINAL_X = 365;    // Signál zpět na původní pozici
        COL_GRID_X = 410;     // Grid s větší mezerou (365 + 45px = 410)
        m_recovery_label_name = "basket_recovery";
    }
    ~CDashboard() {}

    void Initialize(const SSettings &settings, const string &symbols[])
    {
        m_settings = settings; // Uložíme nastavení
        m_chart_id = ChartID();
        m_prefix = "Dashboard_" + (string)m_chart_id + "_";
        m_logger.LogInfo("CDashboard: Inicializace pro chart " + (string)m_chart_id);

        string temp_symbols[];
        ArrayCopy(temp_symbols, symbols);

        // Bubble sort pro seřazení pole stringů
        int n = ArraySize(temp_symbols);
        for(int i = 0; i < n - 1; i++)
        {
            for(int j = 0; j < n - i - 1; j++)
            {
                if(StringCompare(temp_symbols[j], temp_symbols[j + 1]) > 0)
                {
                    string temp = temp_symbols[j];
                    temp_symbols[j] = temp_symbols[j + 1];
                    temp_symbols[j + 1] = temp;
                }
            }
        }
        
        ArrayCopy(m_sorted_symbols, temp_symbols);

        int panel_height = PANEL_ROW_HEIGHT * (ArraySize(m_sorted_symbols) + 1);
        
        DrawPanelBase(panel_height);
        DrawMarketStatusLabel(); // Vykreslíme až po základně, aby bylo nahoře
        DrawRecoveryLabel();
        DrawPanelHeader();

        for(int i = 0; i < ArraySize(m_sorted_symbols); i++)
        {
            DrawSymbolRow(i, m_sorted_symbols[i]);
        }
        ChartRedraw(m_chart_id);
    }
    
    void Update(const SSettings &settings, SSignalInfo &all_signal_info[], const SMarketStatusInfo &status_info)
    {
        m_settings = settings; // Aktualizujeme nastavení pro případ změn
        
        // Aktualizace stavu trhu
        ObjectSetString(m_chart_id, m_prefix + "market_status", OBJPROP_TEXT, status_info.text);
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_COLOR, status_info.text_color);
        UpdateRecoveryLabel();
        
        for(int i = 0; i < ArraySize(m_sorted_symbols); i++)
        {
            string sorted_symbol = m_sorted_symbols[i];
            
            // Najdi odpovídající SSignalInfo
            for(int j = 0; j < ArraySize(all_signal_info); j++)
            {
                if(all_signal_info[j].symbol == sorted_symbol)
                {
                    UpdateRow(sorted_symbol, all_signal_info[j]);
                    break;
                }
            }
        }
        ChartRedraw(m_chart_id);
    }

    void Deinitialize()
    {
        m_logger.LogInfo("CDashboard: Deinicializace a mazání objektů s prefixem: " + m_prefix);
        ObjectsDeleteAll(m_chart_id, m_prefix);
        ChartRedraw(m_chart_id);
    }

private:

    string SignalToString(ENUM_SIGNAL_DIRECTION dir)
    {
        switch(dir)
        {
            case SIGNAL_BUY: return "BUY";
            case SIGNAL_SELL: return "SELL";
            default: return "-";
        }
    }

    color SignalToColor(ENUM_SIGNAL_DIRECTION dir)
    {
        switch(dir)
        {
            case SIGNAL_BUY: return clrLimeGreen;
            case SIGNAL_SELL: return clrTomato;
            default: return clrDimGray;
        }
    }

    void UpdateRow(string symbol, SSignalInfo &info)
    {
        // Zvýraznění aktivního symbolu
        color symbol_color = info.score >= m_settings.MinSymbolScoreToConsider ? m_settings.HighlightColor : clrBlack;
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_label", OBJPROP_COLOR, symbol_color);

        // Score
        ObjectSetString(m_chart_id, m_prefix + symbol + "_score_text", OBJPROP_TEXT, DoubleToString(info.score, 2));
        int max_bar_width = COL_RSI_X - COL_SCORE_X - 15; // Maximální šířka teploměru
        int bar_width = (int)(info.score / 100.0 * max_bar_width);
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_score_bar", OBJPROP_XSIZE, bar_width);
        
        // RSI
        ObjectSetString(m_chart_id, m_prefix + symbol + "_rsi_text", OBJPROP_TEXT, SignalToString(info.rsi_signal));
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_rsi_text", OBJPROP_COLOR, SignalToColor(info.rsi_signal));

        // BB
        ObjectSetString(m_chart_id, m_prefix + symbol + "_bb_text", OBJPROP_TEXT, SignalToString(info.bb_signal));
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_bb_text", OBJPROP_COLOR, SignalToColor(info.bb_signal));

        // Stoch
        ObjectSetString(m_chart_id, m_prefix + symbol + "_stoch_text", OBJPROP_TEXT, SignalToString(info.stoch_signal));
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_stoch_text", OBJPROP_COLOR, SignalToColor(info.stoch_signal));

        // Final
        ObjectSetString(m_chart_id, m_prefix + symbol + "_final_text", OBJPROP_TEXT, SignalToString(info.final_signal));
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_final_text", OBJPROP_COLOR, SignalToColor(info.final_signal));

        // Grid - zobrazí status (úplně vpravo)
        color grid_color = clrDimGray;
        string grid_text = "None";
        if(info.grid_status == GRID_ACTIVE) 
        {
            grid_text = "Active";
            grid_color = clrGoldenrod;
        }
        else if(info.grid_status == GRID_RECOVERING) 
        {
            grid_text = "Recover";
            grid_color = clrOrange;
        }
        ObjectSetString(m_chart_id, m_prefix + symbol + "_grid_text", OBJPROP_TEXT, grid_text);
        ObjectSetInteger(m_chart_id, m_prefix + symbol + "_grid_text", OBJPROP_COLOR, grid_color);
    }

    void DrawPanelBase(int height)
    {
        CreateRectangle(m_prefix + "panel_bg", 0, PANEL_X_POS, PANEL_Y_POS, PANEL_WIDTH, height, PANEL_BG_COLOR, PANEL_BORDER_COLOR);
    }

    void DrawMarketStatusLabel()
    {
        // Vytvoření pozadí pro stavový řádek
        CreateRectangle(m_prefix + "status_bg", 0, PANEL_X_POS, STATUS_LABEL_Y_POS - 2, PANEL_WIDTH, STATUS_ROW_HEIGHT, PANEL_BG_COLOR, PANEL_BORDER_COLOR);

        // Vytvoření samotného textu
        ObjectCreate(m_chart_id, m_prefix + "market_status", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_XDISTANCE, PANEL_X_POS + 10);
        int status_text_y = STATUS_LABEL_Y_POS + (STATUS_ROW_HEIGHT - 14) / 2; // dynamické centrování dle výšky řádku a písma
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_YDISTANCE, status_text_y - 10);
        ObjectSetString(m_chart_id, m_prefix + "market_status", OBJPROP_TEXT, "Načítání stavu trhu...");
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_COLOR, clrGray);
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_FONTSIZE, 14);
        ObjectSetString(m_chart_id, m_prefix + "market_status", OBJPROP_FONT, "Calibri");
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chart_id, m_prefix + "market_status", OBJPROP_BACK, false); // Změna: Popisek patří do popředí
    }


    void DrawPanelHeader()
    {
        int y = PANEL_Y_POS + 2;
        CreateLabel(m_prefix + "header_symbol", 0, COL_SYMBOL_X, y, "Symbol", clrBlack);
        CreateLabel(m_prefix + "header_score", 0, COL_SCORE_X + 8, y, "Score", clrBlack);
        CreateLabel(m_prefix + "header_rsi", 0, COL_RSI_X, y, "RSI", clrBlack);
        CreateLabel(m_prefix + "header_bb", 0, COL_BB_X, y, "BB", clrBlack);
        CreateLabel(m_prefix + "header_stoch", 0, COL_STOCH_X, y, "Stoch", clrBlack);
        CreateLabel(m_prefix + "header_final", 0, COL_FINAL_X, y, "Signál", clrBlack);
        CreateLabel(m_prefix + "header_grid", 0, COL_GRID_X, y, "Grid", clrBlack);
    }

    void DrawRecoveryLabel()
    {
        int y = STATUS_LABEL_Y_POS + 7; // OPRAVA: Posun o trochu níž pro lepší centrování
        int x = PANEL_X_POS + PANEL_WIDTH - 220; // uvnitř status_bg pozadí
        if(x < PANEL_X_POS + 120) x = PANEL_X_POS + 120; // aby nekolidovalo s market_status
        CreateLabel(m_prefix + m_recovery_label_name, 0, x, y, "Rec: 0.00 | Zbyva: 0.00 | Cil: 0.00", clrBlack);
    }

    void UpdateRecoveryLabel()
    {
        // Získáme recovery a realizovaný P/L z globálních proměnných
        double rec = 0.0, realized = 0.0;
        string gv_rec = "CTRex_Recovery_" + (string)m_chart_id;
        string gv_real = "CTRex_Realized_" + (string)m_chart_id;
        if(GlobalVariableCheck(gv_rec)) rec = GlobalVariableGet(gv_rec);
        if(GlobalVariableCheck(gv_real)) realized = GlobalVariableGet(gv_real);
        // Součet otevřeného P/L košíku s daným MagicNumber
        double open_pl = 0.0;
        for(int i=0;i<PositionsTotal();i++)
        {
            ulong t = PositionGetTicket(i);
            if(!PositionSelectByTicket(t)) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.MagicNumber) continue;
            open_pl += PositionGetDouble(POSITION_PROFIT);
        }
        string status_text = "Otevřené P/L: " + DoubleToString(open_pl, 2) + " | Počet: " + (string)PositionsTotal();
        ObjectSetString(m_chart_id, m_prefix + m_recovery_label_name, OBJPROP_TEXT, status_text);
    }
    
    void DrawSymbolRow(int index, string symbol)
    {
        int y = PANEL_Y_POS + (index + 1) * PANEL_ROW_HEIGHT + 2;
        
        CreateLabel(m_prefix + symbol + "_label", 0, COL_SYMBOL_X, y, symbol, clrBlack);
        
        // Score Bar
        int score_bar_width = COL_RSI_X - COL_SCORE_X - 15;
        CreateRectangle(m_prefix + symbol + "_score_bar_bg", 0, COL_SCORE_X + 5, y - 2 + 4, score_bar_width, PANEL_ROW_HEIGHT - 8, SCORE_BAR_BG_COLOR, SCORE_BAR_BG_COLOR);
        CreateRectangle(m_prefix + symbol + "_score_bar", 0, COL_SCORE_X + 5, y - 2 + 4, 0, PANEL_ROW_HEIGHT - 8, SCORE_BAR_COLOR, SCORE_BAR_COLOR);
        
        // Signal Texts
        CreateLabel(m_prefix + symbol + "_score_text", 0, COL_SCORE_X + 8, y, "0.00", clrWhite);
        CreateLabel(m_prefix + symbol + "_rsi_text", 0, COL_RSI_X, y, "-", clrDimGray);
        CreateLabel(m_prefix + symbol + "_bb_text", 0, COL_BB_X, y, "-", clrDimGray);
        CreateLabel(m_prefix + symbol + "_stoch_text", 0, COL_STOCH_X, y, "-", clrDimGray);
        CreateLabel(m_prefix + symbol + "_final_text", 0, COL_FINAL_X, y, "-", clrDimGray);
        CreateLabel(m_prefix + symbol + "_grid_text", 0, COL_GRID_X, y, "-", clrDimGray);
    }

    void CreateRectangle(string name, int sub_window, int x, int y, int width, int height, color bg_color, color border_color)
    {
        ObjectCreate(m_chart_id, name, OBJ_RECTANGLE_LABEL, sub_window, 0, 0);
        ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, width);
        ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, height);
        ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, bg_color);
        ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_COLOR, border_color);
        ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false); // OPRAVA: Obdélníky musí být v popředí (před grafem)
    }

    void CreateLabel(string name, int sub_window, int x, int y, string text, color clr)
    {
        ObjectCreate(m_chart_id, name, OBJ_LABEL, sub_window, 0, 0);
        ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, y);
        ObjectSetString(m_chart_id, name, OBJPROP_TEXT, text);
        ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 8);
        ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Calibri");
        ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
    }
};

