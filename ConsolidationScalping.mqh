//+------------------------------------------------------------------+
//|                                      ConsolidationScalping.mqh |
//|                        Copyright 2024, Investwisdom             |
//|                                    https://www.investwisdom.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Investwisdom"
#property link      "https://www.investwisdom.cz"

#include "Engine.mqh"
#include "Settings.mqh"

// Inputy jsou v hlavním .mq5 souboru - automaticky dostupné po include

//+------------------------------------------------------------------+
//| Manages scalping expert advisor events                           |
//+------------------------------------------------------------------+
class CConsolidationScalping
{
private:
    CEngine* m_engine;

public:
    bool OnInit()
    {
        // Vytvoření nastavení z inputů
        SSettings settings;
        
        // === SCALPING NASTAVENÍ ===
        settings.Scalping_Enabled = InpScalpingEnabled;
        settings.UseRecoveryTrading = InpUseRecoveryTrading;
        settings.Scalping_MaxPositions = InpMaxPositions;
        settings.Scalping_FixedLot = InpFixedLot;
        settings.Scalping_RiskRewardRatio = InpRiskRewardRatio;
        settings.Scalping_MinTPPips = InpMinTPPips;
        settings.Scalping_TrailStepPips = InpTrailStepPips;
        settings.Scalping_TrailLockPips = InpTrailLockPips;
        settings.Scalping_MinScore = (int)InpMinScore;
        // Scalping_MaxPositions už nastaven výše podle trend-only mode
        settings.Scalping_MagicNumber = InpMagicNumber;
        settings.SymbolsToTrade = InpSymbolsToTrade;
        settings.ShowDashboard = InpShowDashboard;
        settings.MinSymbolScoreToConsider = InpMinScore; // Pro Dashboard highlighting
        settings.HighlightColor = InpHighlightColor;
        
        // === SKÓROVÁNÍ NASTAVENÍ ===
        settings.Pouzit_RSI_Pro_Skore = InpUseRSIScoring;
        settings.Pouzit_BB_Pro_Skore = InpUseBBScoring;
        settings.Pouzit_ATR_Pro_Skore = InpUseATRScoring;
        settings.Pouzit_ADX_Pro_Skore = InpUseADXScoring;
        settings.Score_RSI_Top = InpScoreRSITop;
        settings.Score_BB_Ideal = InpScoreBBIdeal;
        settings.Score_BB_Top = InpScoreBBTop;
        settings.Score_ATR_Ideal = InpScoreATRIdeal;
        settings.Score_ATR_Top = InpScoreATRTop;
        settings.Score_ADX_Ideal = InpScoreADXIdeal;
        settings.Score_ADX_Top = InpScoreADXTop;
        
        // === INDIKÁTORY NASTAVENÍ ===
        settings.Stochastic_K = InpStochasticK;
        settings.Stochastic_D = InpStochasticD;
        settings.Stochastic_Slowing = InpStochasticSlowing;
        settings.Stochastic_Oversold = InpStochasticOversold;
        settings.Stochastic_Overbought = InpStochasticOverbought;
        settings.Stochastic_Confirm_Buy_Level = InpStochasticConfirmBuy;
        settings.Stochastic_Confirm_Sell_Level = InpStochasticConfirmSell;
        
        // === BB SLOPE CONFIRMATION ===
        settings.BB_Slope_Threshold_Pips = InpBBSlopeThreshold;
        
        // === TREND PROTECTION ===
        settings.CloseOnTrend = InpCloseOnTrend;
        settings.TrendThreshold = InpTrendThreshold;
        settings.UseEarlyWarning = InpUseEarlyWarning;
        settings.WarningThreshold = InpWarningThreshold;
        settings.BBExpansionThreshold = InpBBExpansionThreshold;
        
        // === RECOVERY TRADING ===
        settings.RecoveryOnSLHit = InpRecoveryOnSLHit;
        settings.RecoveryTargetRatio = InpRecoveryTargetRatio;
        settings.RecoveryLotMultiplier = InpRecoveryLotMultiplier;
        settings.RecoverySLPips = InpRecoverySLPips;
        settings.RecoveryTrailStartPips = InpRecoveryTrailStartPips;
        settings.RecoveryTrailStepPips = InpRecoveryTrailStepPips;
        
        settings.ATR_Period = 14; // ATR perioda je fixní
        settings.RSI_Period = 14; // RSI perioda je fixní (jako v TRex)
        settings.RSI_Prepredano = InpRSIOversold;
        settings.RSI_Prekoupeno = InpRSIOverbought;
        settings.BB_Period = 20; // BB perioda pro skórování je fixní
        settings.BB_Deviation = 2.0; // BB deviation pro skórování je fixní
        settings.BB_Period_Signal = InpBBPeriodSignal;
        settings.BB_Deviation_Signal = InpBBDeviationSignal;
        settings.ADX_Period = InpADXPeriod;
        
        // === SIGNÁLY NASTAVENÍ ===
        settings.Signal_Pouzit_RSI = InpSignalUseRSI;
        settings.Signal_Pouzit_BB = InpSignalUseBB;
        settings.Signal_Pouzit_Stochastic = InpSignalUseStochastic;
        settings.Signal_Logic = InpSignalLogic;
        settings.RequireBBConfirmation = InpRequireBBConfirmation;
        
        // === FILTRY NASTAVENÍ ===
        settings.UseKCSqueezeFilter = InpUseKCSqueezeFilter;
        settings.UseAdxTrendFilter = false; // ADX trend filtr vypnutý pro scalping
        settings.MaxAdxForEntry = 50.0; // Vysoká hodnota = vypnutý filtr
        settings.KC_Period = InpKCPeriod;
        settings.KC_MAPeriod = InpKCMAPeriod;
        settings.KC_Multiplier = InpKCMultiplier;
        settings.KC_MAType = InpKCMAType;
        
        // === ZBÝVAJÍCÍ NASTAVENÍ (nepoužívané pro scalping, ale potřebné pro kompatibilitu) ===
        settings.UseAtrSpikeGuard = false;
        settings.UseAdxFallingGuard = false;
        settings.AdxFallingBars = 3;
        settings.AtrSpikeRatioBlock = 2.0;
        settings.Step_ATR_AvgLookback = 10;
        settings.SqueezePersistenceBars = 0;
        settings.MaxDrawdownPercent = 10.0;
        settings.MagicNumber = InpMagicNumber; // Používá Scalping_MagicNumber

        // Vytvoření a inicializace Engine
        m_engine = new CEngine();
        bool result = m_engine.Initialize(settings);
        
        if(!result)
        {
            Print("❌ CHYBA: Engine se nepodařilo inicializovat!");
            return false;
        }
        
        Print("✅ ConsolidationScalping úspěšně inicializován");
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
        if(CheckPointer(m_engine) == POINTER_DYNAMIC)
        {
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
        if(CheckPointer(m_engine) == POINTER_DYNAMIC)
        {
            m_engine.OnTradeTransaction(trans, request, result);
        }
    }
};