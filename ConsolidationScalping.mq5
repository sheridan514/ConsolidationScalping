//+------------------------------------------------------------------+
//|                                      ConsolidationScalping.mq5 |
//|                        Copyright 2024, Investwisdom             |
//|                                    https://www.investwisdom.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Investwisdom"
#property link      "https://www.investwisdom.cz"
#property version   "1.00"
#property strict

#include "Settings.mqh"              // Enum definice MUSÍ být před inputy!

// === VOLBA STRATEGIE ===
input group "🎯 Strategie Selection"
input bool InpEnableConsolidation = true;    // Povolit konsolidační systém
input bool InpEnableTrend = true;           // Povolit trendový systém

// === KONSOLIDAČNÍ PARAMETRY ===
input group "📊 KONSOLIDACE - Základní"
input string   InpSymbolsToTrade = "EURUSD,GBPUSD,USDJPY"; // Symboly pro trading
input double   InpFixedLot = 0.05;               // Fixní velikost lotu  
input int      InpMagicNumber = 66600;           // Magic number 
input bool     InpScalpingEnabled = true;        // Povolit scalping pozice
input int      InpMaxPositions = 5;              // Maximální počet pozic současně

input group "📊 KONSOLIDACE - Risk Management"
input double   InpRiskRewardRatio = 0.01;        // Risk-Reward Ratio (TP:SL) - menší = SL dále
input int      InpMinTPPips = 3;                 // Minimální TP v pipech (filtr entry)
input int      InpTrailStepPips = 5;             // Krok trailingu po dosažení TP (pipy)
input int      InpTrailLockPips = 10;            // Minimální zisk k uzamčení (pipy)

input group "📊 KONSOLIDACE - Entry"
input double   InpMinScore = 80.0;               // Minimální skóre symbolu pro vstup
input ENUM_SIGNAL_LOGIC InpSignalLogic = LOGIC_HYBRID; // Logika signálů
input bool     InpRequireBBConfirmation = true;  // Vyžadovat BB potvrzení pro signály

input group "📊 KONSOLIDACE - Skórování ADX"
input bool     InpUseADXScoring = true;          // Použít ADX pro skórování
input int      InpADXPeriod = 14;                // Perioda ADX
input double   InpScoreADXIdeal = 18.0;          // ADX: Ideální hodnota pro 100% skóre
input double   InpScoreADXTop = 30.0;            // ADX: Hodnota pro 0% skóre

input group "📊 KONSOLIDACE - Skórování BB"
input bool     InpUseBBScoring = true;           // Použít BB pro skórování
input double   InpScoreBBIdeal = 0.15;           // Šířka BB %: Ideální hodnota pro 100% skóre
input double   InpScoreBBTop = 0.25;             // Šířka BB %: Hodnota pro 0% skóre

input group "📊 KONSOLIDACE - Skórování ATR"
input bool     InpUseATRScoring = true;          // Použít ATR pro skórování
input double   InpScoreATRIdeal = 0.07;          // ATR %: Ideální hodnota pro 100% skóre
input double   InpScoreATRTop = 0.13;            // ATR %: Hodnota pro 0% skóre

input group "📊 KONSOLIDACE - Skórování RSI"
input bool     InpUseRSIScoring = false;         // Použít RSI pro skórování
input double   InpScoreRSITop = 100.0;           // RSI: Hodnota pro 100% skóre

input group "📊 KONSOLIDACE - Signály BB"
input bool     InpSignalUseBB = true;            // Použít BB jako spouštěč
input int      InpBBPeriodSignal = 20;           // Perioda BB (pro signál)
input double   InpBBDeviationSignal = 2.0;       // Odchylka BB (pro signál)

input group "📊 KONSOLIDACE - Signály RSI"
input bool     InpSignalUseRSI = false;          // Použít RSI jako spouštěč signálu
input double   InpRSIOverbought = 70.0;          // RSI: Úroveň překoupenosti
input double   InpRSIOversold = 30.0;            // RSI: Úroveň přeprodanosti

input group "📊 KONSOLIDACE - Signály Stochastic"
input bool     InpSignalUseStochastic = true;    // Použít Stochastic jako spouštěč
input int      InpStochasticK = 14;              // Perioda %K
input int      InpStochasticD = 3;               // Perioda %D
input int      InpStochasticSlowing = 3;         // Zpomalení
input double   InpStochasticOverbought = 70.0;   // Překoupená úroveň
input double   InpStochasticOversold = 30.0;     // Přeprodaná úroveň
input double   InpStochasticConfirmBuy = 32.0;   // Potvrzovací úroveň pro BUY 
input double   InpStochasticConfirmSell = 75.0;  // Potvrzovací úroveň pro SELL

input group "📊 KONSOLIDACE - BB Slope"
input double   InpBBSlopeThreshold = 0.1;        // BB sklon threshold (pipy)

input group "📊 KONSOLIDACE - Trend Protection"
input bool     InpCloseOnTrend = true;           // Uzavřít pozice při detekci trendu
input double   InpTrendThreshold = 60.0;         // Score threshold pro trend
input bool     InpUseEarlyWarning = true;        // Early warning detekci konce konsolidace
input double   InpWarningThreshold = 65.0;      // Score threshold pro varování
input double   InpBBExpansionThreshold = 1.2;   // BB expansion ratio threshold

input group "📊 KONSOLIDACE - Recovery Trading"
input bool     InpUseRecoveryTrading = true;        // Aktivovat recovery trading
input bool     InpRecoveryOnSLHit = false;          // Recovery při každém SL hit
input double   InpRecoveryTargetRatio = 1.5;       // Cílový poměr k pokrytí ztráty
input double   InpRecoveryLotMultiplier = 1.5;     // Násobič lot size pro recovery
input int      InpRecoverySLPips = 20;             // Počáteční SL pro recovery pozice
input int      InpRecoveryTrailStartPips = 3;       // Kdy začít trailing
input int      InpRecoveryTrailStepPips = 2;         // Krok trailing SL

input group "📊 KONSOLIDACE - Filtry"
input bool     InpUseKCSqueezeFilter = false;     // KC Squeeze filtr
input int      InpKCPeriod = 20;                 // Perioda Keltnerova Kanálu
input int      InpKCMAPeriod = 20;               // Perioda MA pro ATR
input double   InpKCMultiplier = 1.5;            // Násobič ATR pro šířku kanálu
input ENUM_MA_METHOD InpKCMAType = MODE_EMA;     // Typ klouzavého průměru

input group "📊 KONSOLIDACE - Vizuál"
input bool     InpShowDashboard = true;         // Zobrazit dashboard
input color    InpHighlightColor = clrRed;       // Barva pro zvýraznění

// === TRENDOVÉ PARAMETRY ===
input group "📈 TRENDY - Trading"
input bool     InpTrendEnabled = true;           // Povolit trendové pozice
input double   InpTrendFixedLot = 0.05;         // Fixní velikost lotu pro trendy
input int      InpTrendMagicNumber = 66601;     // Magic number pro trendy
input int      InpTrendMaxPositions = 3;        // Max trendových pozic současně
input double   InpTrendScoreThreshold = 35.0;   // Score threshold pro trend entry (velmi nízké = silný trend)

input group "📈 TRENDY - Risk Management"  
input int      InpTrendSLPips = 25;             // Počáteční SL pro trendové pozice
input int      InpTrendMinTPPips = 15;          // Minimální TP pro trend entry
input int      InpTrendTrailStartPips = 12;     // Kdy začít trailing
input int      InpTrendTrailStepPips = 8;       // Krok trailing SL

input group "📈 TRENDY - Detection"
input double   InpBBExpansionRatio = 1.5;       // BB expansion minimum (50% růst šířky = silná expanze)
input double   InpMinADXForTrend = 28.0;        // Minimální ADX pro trend potvrzení (vyšší = silnější trend)
input int      InpMomentumBars = 5;             // Počet consecutive svíček pro momentum (více = silnější trend)
input int      InpTrendEMAPeriod = 21;          // EMA perioda pro trend směr potvrzení
input int      InpTrendStochasticK = 14;        // Stochastic %K perioda pro trendy
input int      InpTrendStochasticD = 3;         // Stochastic %D perioda pro trendy
input int      InpTrendStochasticSlowing = 3;   // Stochastic slowing pro trendy
input double   InpTrendStochasticLow = 20.0;    // Spodní hranice pro trend momentum
input double   InpTrendStochasticHigh = 80.0;   // Horní hranice pro trend momentum

#include "ConsolidationScalping.mqh" // Konsolidační strategie
#include "TrendEngine.mqh"            // Trendový engine
#include "TrendScalping.mqh"          // Trendová strategie

CConsolidationScalping consolidation_manager; // Konsolidační systém
CTrendScalping trend_manager;                  // Trendový systém

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Kontrola, že aspoň jeden systém je povolen
   if(!InpEnableConsolidation && !InpEnableTrend)
   {
       Print("❌ CHYBA: Musíte povolit alespoň jeden systém!");
       return(INIT_FAILED);
   }
   
   // Inicializace konsolidačního systému - inputy jsou globální
   if(InpEnableConsolidation)
   {
       if(!consolidation_manager.OnInit())
       {
           Print("❌ CHYBA: ConsolidationScalping inicializace selhala!");
           return(INIT_FAILED);
       }
       Print("✅ KONSOLIDACE: Magic 66600 - Score 80+ aktivní");
   }
   
   // Inicializace trendového systému - inputy jsou globální
   if(InpEnableTrend)
   {
       if(!trend_manager.OnInit())
       {
           Print("❌ CHYBA: TrendScalping inicializace selhala!");
           return(INIT_FAILED);
       }
       Print("✅ TRENDY: Magic 66601 - Score <60 aktivní");
   }
   
   // Výpis aktivních systémů
   string active_systems = "";
   if(InpEnableConsolidation && InpEnableTrend)
       active_systems = "🎯 HYBRID SYSTEM: Konsolidace + Trendy";
   else if(InpEnableConsolidation)
       active_systems = "📊 CONSOLIDATION ONLY: Mean reversion";
   else if(InpEnableTrend)
       active_systems = "📈 TREND ONLY: Momentum breakouts";
   
   Print(active_systems + " - System ready!");
   
   TesterHideIndicators(true); 
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpEnableConsolidation)
       consolidation_manager.OnDeinit(reason);
       
   if(InpEnableTrend)
       trend_manager.OnDeinit(reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Spustit pouze aktivní systémy
   if(InpEnableConsolidation)
       consolidation_manager.OnTick(); // Score 80+ = konsolidační obchody
       
   if(InpEnableTrend)
       trend_manager.OnTick();         // Score <60 = trendové obchody
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpEnableConsolidation)
       consolidation_manager.OnTimer();
       
   if(InpEnableTrend)
       trend_manager.OnTimer();
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(InpEnableConsolidation)
       consolidation_manager.OnTradeTransaction(trans, request, result);
       
   if(InpEnableTrend)
       trend_manager.OnTradeTransaction(trans, request, result);
}
//+------------------------------------------------------------------+