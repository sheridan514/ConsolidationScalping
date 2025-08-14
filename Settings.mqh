//+------------------------------------------------------------------+
//|                                                   Settings.mqh |
//|                        Copyright 2024, Tomas Nezval              |
//|                                             https://www.nezval.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Tomas Nezval"
#property link      "https://www.nezval.cz"

// Signály (stejné jako ConsolidationTRex)
enum ENUM_SIGNAL_DIRECTION
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY = 1,
    SIGNAL_SELL = -1
};

enum ENUM_SIGNAL_LOGIC
{
    LOGIC_ALL = 0,
    LOGIC_HYBRID = 1
};

enum ENUM_GRID_STATUS
{
    GRID_NONE = 0,
    GRID_ACTIVE = 1,
    GRID_RECOVERING = 2
};

// Struktura pro informace o signálu
struct SSignalInfo
{
    string symbol;
    double score;
    ENUM_SIGNAL_DIRECTION final_signal;
    ENUM_SIGNAL_DIRECTION rsi_signal;
    ENUM_SIGNAL_DIRECTION bb_signal;
    ENUM_SIGNAL_DIRECTION stoch_signal;
    ENUM_GRID_STATUS grid_status;
    bool has_position; // Přidáno pro Dashboard
};

// Struktura pro market status (Dashboard)
struct SMarketStatusInfo
{
    string text;
    color text_color;
    
    // Copy constructor pro zabránění warningů
    SMarketStatusInfo(const SMarketStatusInfo &other)
    {
        text = other.text;
        text_color = other.text_color;
    }
    
    SMarketStatusInfo() {} // Default constructor
};

// Struktura pro indikátorový otisk
struct SIndicatorSnapshot
{
    double score;
    double rsi;
    double bb_width_pct;
    double atr_pct;
    double adx;
};

// Hlavní nastavení (přizpůsobené pro scalping)
struct SSettings
{
               // === SCALPING NASTAVENÍ ===
    bool   Scalping_Enabled;
    double Scalping_FixedLot;
       double Scalping_RiskRewardRatio;
       int    Scalping_MinTPPips;
       int    Scalping_TrailStepPips;
       int    Scalping_TrailLockPips;
       int    Scalping_MinScore;
       int    Scalping_MaxPositions;
       int    Scalping_MagicNumber;
       int    Scalping_SLPips;          // Přidáno pro trendový systém
       string SymbolsToTrade;
    
           // === ZÁKLADNÍ NASTAVENÍ (minimální pro scalping) ===
       bool   ShowDashboard;
       double MinSymbolScoreToConsider;
       color  HighlightColor;
    
    // === FILTER NASTAVENÍ (pro kompatibilitu) ===
    int    Stochastic_K;
    int    Stochastic_D;
    int    Stochastic_Slowing;
    double Stochastic_Oversold;
    double Stochastic_Overbought;
    double Stochastic_Confirm_Buy_Level;
    double Stochastic_Confirm_Sell_Level;
    
    // === BB SLOPE CONFIRMATION ===
    double BB_Slope_Threshold_Pips;
    
    // === TREND PROTECTION ===
    bool   CloseOnTrend;
    double TrendThreshold;
    bool   UseEarlyWarning;
    double WarningThreshold;
    double BBExpansionThreshold;
    
    // === RECOVERY TRADING ===
    bool   UseRecoveryTrading;
    bool   RecoveryOnSLHit;
    double RecoveryTargetRatio;
    double RecoveryLotMultiplier;
    int    RecoverySLPips;
    int    RecoveryTrailStartPips;
    int    RecoveryTrailStepPips;
    

    
    int    ATR_Period;
    int    RSI_Period;
    double RSI_Prepredano;
    double RSI_Prekoupeno;
    int    BB_Period;
    double BB_Deviation;
    int    BB_Period_Signal;
    double BB_Deviation_Signal;
    int    ADX_Period;
    int    KC_Period;
    int    KC_MAPeriod;
    int    KC_MAType;
    double KC_Multiplier;
    bool   Pouzit_RSI_Pro_Skore;
    bool   Pouzit_BB_Pro_Skore;
    bool   Pouzit_ATR_Pro_Skore;
    bool   Pouzit_ADX_Pro_Skore;
    bool   Signal_Pouzit_RSI;
    bool   Signal_Pouzit_BB;
    bool   Signal_Pouzit_Stochastic;
    int    Signal_Logic;
    bool   RequireBBConfirmation;
    bool   UseKCSqueezeFilter;
    bool   UseAdxTrendFilter;
    double MaxAdxForEntry;
    double Score_RSI_Top;
    double Score_BB_Ideal;
    double Score_BB_Top;
    double Score_ATR_Ideal;
    double Score_ATR_Top;
    double Score_ADX_Ideal;
    double Score_ADX_Top;
    bool   UseAtrSpikeGuard;
    bool   UseAdxFallingGuard;
    int    AdxFallingBars;
    double AtrSpikeRatioBlock;
    int    Step_ATR_AvgLookback;
    int    SqueezePersistenceBars;
    double MaxDrawdownPercent;
    int    MagicNumber;
};
