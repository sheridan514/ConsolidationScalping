//+------------------------------------------------------------------+
//|                                         TrendScalping.mqh |
//|                        Copyright 2024, Investwisdom             |
//|                                    https://www.investwisdom.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Investwisdom"
#property link      "https://www.investwisdom.cz"

#include "TrendEngine.mqh"
#include "Settings.mqh"

// Inputy jsou v hlavním .mq5 souboru - automaticky dostupné po include

//+------------------------------------------------------------------+
//| Manages trend scalping expert advisor events                    |
//+------------------------------------------------------------------+
class CTrendScalping
{
private:
    CTrendEngine* m_engine;
    SSettings m_settings;
    
public:
    bool OnInit()
    {
        // Vytvoření nastavení pro trendový systém
        SSettings settings;
        
        // === ZÁKLADNÍ NASTAVENÍ ===
        settings.Scalping_Enabled = false;  // VYPNOUT Engine scalping - my ho nebudeme používat!
        settings.Scalping_FixedLot = InpTrendFixedLot;
        settings.Scalping_MagicNumber = InpTrendMagicNumber;  // VLASTNÍ magic number pro trendy!
        settings.Scalping_MaxPositions = InpTrendMaxPositions;
        settings.Scalping_MinScore = (int)InpTrendScoreThreshold;
        settings.Scalping_MinTPPips = InpTrendMinTPPips;
        settings.Scalping_TrailStepPips = InpTrendTrailStepPips;
        settings.Scalping_TrailLockPips = InpTrendTrailStartPips;
        settings.Scalping_SLPips = InpTrendSLPips;  // Předat správný SL parametr
        
        // === SDÍLENÉ NASTAVENÍ ===
        settings.SymbolsToTrade = InpSymbolsToTrade;
        settings.ShowDashboard = true; // Povolit dashboard i pro trendy
        
        // === INDIKÁTORY ===
        settings.ATR_Period = 14;
        settings.RSI_Period = 14;
        settings.BB_Period = 20;
        settings.BB_Deviation = 2.0;
        settings.BB_Period_Signal = 20;
        settings.BB_Deviation_Signal = 2.0;
        settings.ADX_Period = 14;
        
        // === TRENDOVÉ SKÓROVÁNÍ ===
        settings.Pouzit_RSI_Pro_Skore = false;
        settings.Pouzit_BB_Pro_Skore = true;
        settings.Pouzit_ATR_Pro_Skore = true;
        settings.Pouzit_ADX_Pro_Skore = true;
        
        // TRENDOVÉ SKÓROVÁNÍ: Chceme nízké skóre pro trendy!
        settings.Score_BB_Ideal = 0.35;    // Široké BB = ideální pro trendy
        settings.Score_BB_Top = 0.15;      // Úzké BB = vysoké skóre (konsolidace)
        settings.Score_ATR_Ideal = 0.20;   // Vysoká ATR = ideální pro trendy
        settings.Score_ATR_Top = 0.07;     // Nízká ATR = vysoké skóre (konsolidace)
        settings.Score_ADX_Ideal = 35.0;   // Vysoký ADX = ideální pro trendy
        settings.Score_ADX_Top = 18.0;     // Nízký ADX = vysoké skóre (konsolidace)
        
        // === SIGNÁLY PRO TRENDY ===
        settings.Signal_Pouzit_RSI = false;
        settings.Signal_Pouzit_BB = true;
        settings.Signal_Pouzit_Stochastic = true;
        settings.Signal_Logic = LOGIC_HYBRID;
        settings.RequireBBConfirmation = true;
        
        // === STOCHASTIC PRO TRENDY ===
        settings.Stochastic_K = InpTrendStochasticK;
        settings.Stochastic_D = InpTrendStochasticD;
        settings.Stochastic_Slowing = InpTrendStochasticSlowing;
        settings.Stochastic_Oversold = InpTrendStochasticLow;
        settings.Stochastic_Overbought = InpTrendStochasticHigh;
        settings.Stochastic_Confirm_Buy_Level = InpTrendStochasticLow;
        settings.Stochastic_Confirm_Sell_Level = InpTrendStochasticHigh;
        
        // === TREND PROTECTION ===
        settings.CloseOnTrend = false;            // NIKDY neuzavírat při trendu!
        settings.UseEarlyWarning = false;         // Nepotřebujeme varování
        settings.TrendThreshold = 60.0;           // Naše entry threshold
        
        // === VYPNOUT ENGINE AUTO-MANAGEMENTY ===
        settings.UseRecoveryTrading = false;      // Žádné Engine recovery!
        settings.UseKCSqueezeFilter = false;      // Žádné filtry
        settings.UseAdxTrendFilter = false;       // Žádné ADX management
        
        // === FILTRY ===
        settings.MaxAdxForEntry = 100.0;          // Žádný ADX limit
        settings.BB_Slope_Threshold_Pips = 1.0;   // Větší slope requirement
        settings.BBExpansionThreshold = InpBBExpansionRatio;
        
        // === OSTATNÍ NASTAVENÍ ===
        settings.UseAtrSpikeGuard = false;        // Chceme volatilitu pro trendy
        settings.UseAdxFallingGuard = false;
        settings.MagicNumber = InpTrendMagicNumber;
        
        // === TRENDOVÉ SKÓROVÁNÍ - VYPNUTÍ PENALTY ===
        settings.WarningThreshold = 100.0;        // Vypnout early warning penalty
        
        // Uložit nastavení
        m_settings = settings;
        
        // Vytvoření a inicializace TrendEngine
        m_engine = new CTrendEngine();
        bool result = m_engine.Initialize(settings);
        
        if(!result)
        {
            Print("❌ CHYBA: TrendEngine se nepodařilo inicializovat!");
            return false;
        }

        Print("✅ TrendScalping úspěšně inicializován (Magic: " + IntegerToString(InpTrendMagicNumber) + ")");
        return true;
    }

    void OnDeinit(const int reason)
    {
        if(CheckPointer(m_engine) == POINTER_DYNAMIC)
        {
            m_engine.Deinitialize(reason);
            delete m_engine;
            m_engine = NULL;
        }
    }

    void OnTick()
    {
        if(!InpTrendEnabled) return;
        
        if(CheckPointer(m_engine) == POINTER_DYNAMIC)
        {
            // Předat tick do TrendEngine
            m_engine.OnTick();
        }
    }
    
    void OnTimer()
    {
        if(CheckPointer(m_engine) == POINTER_DYNAMIC)
        {
            m_engine.OnTimer();
        }
    }
    
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
    {
        // TrendEngine si sám spravuje pozice
    }
};
