//+------------------------------------------------------------------+
//|                                                     Filter.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include "Settings.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Třída pro technickou analýzu                                     |
//+------------------------------------------------------------------+
class CFilter
{
private:
    SSettings m_settings;
    CLogger m_logger;
    
public:
    CFilter() {}
    ~CFilter() {}

    bool Initialize(const SSettings &settings)
    {
        m_settings = settings;
        // m_logger.LogInfo("CFilter: Inicializace dokončena");
        return true;
    }

    // Forward deklarace pro metody používané v jiných metodách
    double GetRsiValue(const string symbol)
    {
        int handle = iRSI(symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return -1;
        
        double rsi[];
        ArraySetAsSeries(rsi, true);
        if(CopyBuffer(handle, 0, 0, 2, rsi) < 2)
        {
            IndicatorRelease(handle);
            return -1;
        }
        IndicatorRelease(handle);
        return rsi[1];
    }

    ENUM_SIGNAL_DIRECTION CheckStochasticSignal(const string symbol)
    {
        int stoch_handle = iStochastic(symbol, PERIOD_CURRENT, m_settings.Stochastic_K, m_settings.Stochastic_D, m_settings.Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
        if(stoch_handle == INVALID_HANDLE) 
        {
            m_logger.LogInfo("🔍 " + symbol + " - Stochastic handle INVALID");
            return SIGNAL_NONE;
        }
        
        double main[], sig[];
        ArraySetAsSeries(main, true);
        ArraySetAsSeries(sig, true);
        
        // Potřebujeme více historie pro logiku "setup + confirmation"
        int main_copied = CopyBuffer(stoch_handle, 0, 0, 5, main);
        int sig_copied = CopyBuffer(stoch_handle, 1, 0, 5, sig);
        
        if(main_copied < 3 || sig_copied < 3) // Minimálně 3 vzorky místo 5
        {
            // Na začátku backtestingu může být nedostatek dat - ne chyba
            IndicatorRelease(stoch_handle);
            return SIGNAL_NONE;
        }
        IndicatorRelease(stoch_handle);
        
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 5, rates) < 3) // Minimálně 3 vzorky
        {
            m_logger.LogInfo("🔍 " + symbol + " - CopyRates failed");
            return SIGNAL_NONE;
        }

        bool buy_setup = false;
        bool sell_setup = false;
        
        // Používáme aktuální svíčku pro rychlejší signály
        int bar_idx = 0; 

        // bar_idx = 0 -> aktuální svíčka (neuzavřená)
        // bar_idx+1 = 1 -> poslední uzavřená svíčka  
        // bar_idx+2 = 2 -> předchozí uzavřená svíčka
        
        // KROK 1: Identifikace SETUPU - zjednodušená logika pro konsolidaci
        // Stochastic je v přeprodané/překoupené zóně (přechozí svíčka)
        buy_setup = main[bar_idx+1] < m_settings.Stochastic_Oversold;
        sell_setup = main[bar_idx+1] > m_settings.Stochastic_Overbought;
        


        // KROK 2: Hledání silného POTVRZENÍ na aktuální svíčce (index 0)
        if(buy_setup)
        {
            // Potvrzení: Stochastic musí vystoupat nad konfigurovatelnou úroveň.
            bool buy_confirm = main[bar_idx] > m_settings.Stochastic_Confirm_Buy_Level;
            if(buy_confirm)
            {
                return SIGNAL_BUY;
            }
        }
        
        if(sell_setup)
        {
            // Potvrzení: Stochastic zůstává nad konfigurovatelnou úrovní (síla SELL signálu).
            bool sell_confirm = main[bar_idx] > m_settings.Stochastic_Confirm_Sell_Level;
            if(sell_confirm)
            {
                return SIGNAL_SELL;
            }
        }
        
        return SIGNAL_NONE;
    }

    double GetSymbolScore(const string symbol)
    {
        double total_score = 0;
        int active_modules = 0;

        if(m_settings.Pouzit_RSI_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_BB_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_ATR_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_ADX_Pro_Skore) active_modules++;

        if(active_modules == 0) return 100.0;

        double module_weight = 100.0 / active_modules;

        if(m_settings.Pouzit_RSI_Pro_Skore) total_score += GetRsiScore(symbol, module_weight);
        if(m_settings.Pouzit_BB_Pro_Skore) total_score += GetBbScore(symbol, module_weight);
        if(m_settings.Pouzit_ATR_Pro_Skore) total_score += GetAtrScore(symbol, module_weight);
        if(m_settings.Pouzit_ADX_Pro_Skore) total_score += GetAdxScore(symbol, module_weight);
        
        // Early warning penalty - snížit score pokud se blíží konec konsolidace
        if(m_settings.UseEarlyWarning)
        {
            total_score = ApplyEarlyWarningPenalty(symbol, total_score);
        }
        
        return total_score;
    }
    
    double ApplyEarlyWarningPenalty(const string symbol, double base_score)
    {
        // === POKROČILÁ ANALÝZA EARLY WARNING SIGNÁLŮ ===
        double penalty_factor = 1.0; // Začneme s žádnou penalty
        
        // 1. BB EXPANSION ANALYSIS (rozšiřování pásem)
        bool bb_expanding = IsBBExpanding(symbol);
        if(bb_expanding)
        {
            penalty_factor *= 0.6; // 40% penalty za BB expansion
        }
        
        // 2. VOLATILITA TRENDY (ATR růst)
        double atr_trend = GetATRTrend(symbol);
        if(atr_trend > 1.15) // ATR roste o více než 15%
        {
            penalty_factor *= 0.75; // 25% penalty za rostoucí volatilitu
        }
        
        // 3. PRICE MOMENTUM (rychlost změny ceny)
        double price_momentum = GetPriceMomentum(symbol);
        if(price_momentum > 0.5) // Významný momentum
        {
            penalty_factor *= 0.8; // 20% penalty za momentum
        }
        
        // 4. BB POZICE (jak daleko je cena od středu)
        double bb_position = GetBBPosition(symbol);
        if(bb_position > 0.7) // Cena blízko krajních pásem
        {
            penalty_factor *= 0.85; // 15% penalty za extrémní pozici
        }
        
        // 5. SCORE PROXIMITY (blížící se warning threshold)
        double score_vs_warning = base_score / m_settings.WarningThreshold;
        if(base_score < m_settings.WarningThreshold * 1.2) // V rámci 20% od warning threshold
        {
            penalty_factor *= score_vs_warning; // Progresivní penalty
        }
        
        // 3. Multi-symbol context penalty
        double market_penalty = GetMarketWidePenalty();
        penalty_factor *= market_penalty;
        
        double penalized_score = base_score * penalty_factor;
        
        // Log pouze pokud je penalty významná

        
        return penalized_score;
    }
    
    // === POKROČILÉ EARLY WARNING METODY ===
    
    double GetATRTrend(const string symbol)
    {
        // Porovnání současné ATR s ATR před 10 svíčkami
        int atr_handle = iATR(symbol, PERIOD_CURRENT, 14);
        if(atr_handle == INVALID_HANDLE) return 1.0;
        
        double atr_buffer[];
        ArraySetAsSeries(atr_buffer, true);
        
        if(CopyBuffer(atr_handle, 0, 0, 11, atr_buffer) < 11)
        {
            IndicatorRelease(atr_handle);
            return 1.0;
        }
        
        double current_atr = atr_buffer[0];
        double past_atr = atr_buffer[10];
        
        IndicatorRelease(atr_handle);
        
        if(past_atr <= 0) return 1.0;
        return current_atr / past_atr; // > 1.0 = rostoucí volatilita
    }
    
    double GetPriceMomentum(const string symbol)
    {
        // Rychlost změny ceny (ROC - Rate of Change)
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 6, rates) < 6)
            return 0.0;
            
        double current_close = rates[0].close;
        double past_close = rates[5].close;
        
        if(past_close <= 0) return 0.0;
        
        double price_change = MathAbs((current_close - past_close) / past_close);
        return price_change; // 0-1+ (0=žádná změna, 1=100% změna)
    }
    
    double GetBBPosition(const string symbol)
    {
        // Kde se nachází cena vzhledem k BB pásmu (0=dolní, 0.5=střed, 1=horní)
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return 0.5;
        
        double upper_buffer[], lower_buffer[], middle_buffer[];
        ArraySetAsSeries(upper_buffer, true);
        ArraySetAsSeries(lower_buffer, true);
        ArraySetAsSeries(middle_buffer, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 1, upper_buffer) < 1 ||
           CopyBuffer(bb_handle, 2, 0, 1, lower_buffer) < 1 ||
           CopyBuffer(bb_handle, 0, 0, 1, middle_buffer) < 1)
        {
            IndicatorRelease(bb_handle);
            return 0.5;
        }
        
        IndicatorRelease(bb_handle);
        
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double upper = upper_buffer[0];
        double lower = lower_buffer[0];
        
        if(upper <= lower) return 0.5;
        
        // Normalizovaná pozice (0-1)
        double position = (current_price - lower) / (upper - lower);
        return MathMax(0.0, MathMin(1.0, position));
    }
    
    double GetMarketWidePenalty()
    {
        // Jednoduchá implementace - vždy vrátí 1.0 (žádná penalty)
        // V budoucnu by zde mohla být analýza celého trhu
        return 1.0;
    }

    ENUM_SIGNAL_DIRECTION GetRsiSignal(const string symbol)
    {
        int handle = iRSI(symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return SIGNAL_NONE;

        double rsi[];
        ArraySetAsSeries(rsi, true);        
        if(CopyBuffer(handle, 0, 0, 5, rsi) < 5)
        {
            IndicatorRelease(handle);
            return SIGNAL_NONE;
        }
        IndicatorRelease(handle);

        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 5, rates) < 5)
        {
            return SIGNAL_NONE;
        }

        // bar_idx = 1 -> potvrzovací svíčka
        // bar_idx+1 = 2 -> setup svíčka
        int bar_idx = 1;

        // KROK 1: SETUP na před-předchozí svíčce (index 2)
        bool buy_setup = rsi[bar_idx+2] < m_settings.RSI_Prepredano && rsi[bar_idx+1] > m_settings.RSI_Prepredano;
        bool sell_setup = rsi[bar_idx+2] > m_settings.RSI_Prekoupeno && rsi[bar_idx+1] < m_settings.RSI_Prekoupeno;
        
        // KROK 2: POTVRZENÍ na poslední uzavřené svíčce (index 1)
        if (buy_setup && rates[bar_idx].close > rates[bar_idx+1].close)
        {
            return SIGNAL_BUY;
        }
        if (sell_setup && rates[bar_idx].close < rates[bar_idx+1].close)
        {
            return SIGNAL_SELL;
        }

        return SIGNAL_NONE;
    }

    // NOVÁ FUNKCE: Bollinger Bands signál pro dashboard
    ENUM_SIGNAL_DIRECTION GetBollingerSignal(const string symbol)
    {
        // Použije stejnou logiku jako ConfirmWithBollingerBands
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 3, rates) < 3) return SIGNAL_NONE;

        int handle = iBands(symbol, PERIOD_CURRENT, m_settings.BB_Period, 0, m_settings.BB_Deviation, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return SIGNAL_NONE;

        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        if(CopyBuffer(handle, 1, 0, 3, upper) < 3 || CopyBuffer(handle, 2, 0, 3, lower) < 3)
        {
            IndicatorRelease(handle);
            return SIGNAL_NONE;
        }
        IndicatorRelease(handle);

        int bar_idx = 1; // Poslední uzavřená svíčka

        // BUY signál: Cena se dotýká spodního pásma a odráží se nahoru
        if(rates[bar_idx+1].low <= lower[bar_idx+1] && rates[bar_idx].close > rates[bar_idx+1].close)
        {
            return SIGNAL_BUY;
        }
        
        // SELL signál: Cena se dotýká horního pásma a odráží se dolů
        if(rates[bar_idx+1].high >= upper[bar_idx+1] && rates[bar_idx].close < rates[bar_idx+1].close)
        {
            return SIGNAL_SELL;
        }

        return SIGNAL_NONE;
    }

    // NOVÁ FUNKCE: Stochastic signál pro dashboard
    ENUM_SIGNAL_DIRECTION GetStochasticSignal(const string symbol)
    {
        // Použije stejnou logiku jako CheckStochasticSignal
        return CheckStochasticSignal(symbol);
    }

    ENUM_SIGNAL_DIRECTION GetCombinedSignal(const string symbol)
    {
        ENUM_SIGNAL_DIRECTION signals_found[];
        int signal_count = 0;

        if(m_settings.Signal_Pouzit_RSI)
        {
            ArrayResize(signals_found, signal_count + 1);
            signals_found[signal_count] = GetRsiSignal(symbol);
            signal_count++;
        }
        if(m_settings.Signal_Pouzit_BB)
        {
             // V hybridní logice se BB používá jen jako potvrzení, ne jako samostatný signál.
             // Pro jiné logiky by zde bylo volání GetBbSignal(symbol).
        }
        if(m_settings.Signal_Pouzit_Stochastic)
        {
            ArrayResize(signals_found, signal_count + 1);
            signals_found[signal_count] = CheckStochasticSignal(symbol);
            signal_count++;
        }

        if(signal_count == 0) return SIGNAL_NONE;

        if(m_settings.Signal_Logic == LOGIC_HYBRID)
        {
            if (!m_settings.Signal_Pouzit_Stochastic)
            {
                return SIGNAL_NONE;
            }

            ENUM_SIGNAL_DIRECTION stoch_signal = CheckStochasticSignal(symbol);
            
            if(stoch_signal == SIGNAL_NONE) 
            {
                return SIGNAL_NONE;
            }

            // BB potvrzení je volitelné
            if(m_settings.RequireBBConfirmation && m_settings.Signal_Pouzit_BB)
            {
                if(ConfirmWithBollingerBands(symbol, stoch_signal))
                {
                    // Zkontrolovat i sklon BB prostřední čáry
                    if(!ConfirmWithBBSlope(symbol, stoch_signal))
                    {
                        return SIGNAL_NONE; // Signál proti sklonu BB
                    }
                    return stoch_signal;
                }
                else
                {
                    return SIGNAL_NONE;
                }
            }
            else
            {
                // I bez BB potvrzení zkontrolovat sklon
                if(!ConfirmWithBBSlope(symbol, stoch_signal))
                {
                    return SIGNAL_NONE; // Signál proti sklonu BB
                }
                return stoch_signal;
            }
        }
        else if(m_settings.Signal_Logic == LOGIC_ALL)
        {
            ENUM_SIGNAL_DIRECTION first_signal = signals_found[0];
                               if(first_signal == SIGNAL_NONE) return SIGNAL_NONE;

            for(int i = 1; i < signal_count; i++)
            {
                if(signals_found[i] != first_signal)
                {
                    return SIGNAL_NONE;
                }
            }
            return first_signal;
        }
        else // LOGIC_ANY
        {
            for(int i = 0; i < signal_count; i++)
            {
                if(signals_found[i] != SIGNAL_NONE                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           )
                {
                    return signals_found[i];
                }
            }
            return SIGNAL_NONE;
        }
    }

    // Veřejné pomocné metody pro konsolidační guardy
    bool IsKcSqueeze(const string symbol, int shift = 0)
    {
        return IsInKCSqueeze(symbol, shift);
    }

    double GetAtrAverage(const string symbol, int period, int lookback)
    {
        int h = iATR(symbol, PERIOD_CURRENT, period);
        if(h == INVALID_HANDLE) return -1;
        int n = MathMax(lookback, 10);
        double b[]; ArraySetAsSeries(b,true);
        if(CopyBuffer(h,0,0,n+1,b) < n+1){ IndicatorRelease(h); return -1; }
        IndicatorRelease(h);
        double sum=0; for(int i=1;i<=n;i++) sum += b[i];
        return sum / n;
    }

    //------------------------------------------------------------------
    // NOVÁ VEŘEJNÁ METODA pro získání kompletního otisku indikátorů
    //------------------------------------------------------------------
    SIndicatorSnapshot GetIndicatorSnapshot(const string symbol)
    {
        SIndicatorSnapshot snapshot;
        snapshot.score = GetSymbolScore(symbol);
        snapshot.rsi = GetRsiValue(symbol);
        snapshot.bb_width_pct = GetBbWidthPercent(symbol);
        snapshot.atr_pct = GetAtrPercent(symbol);
        snapshot.adx = GetAdxValue(symbol);
        return snapshot;
    }

    //------------------------------------------------------------------
    // NOVÁ VEŘEJNÁ METODA pro získání čisté hodnoty ATR
    //------------------------------------------------------------------
    double GetAtrValue(const string symbol)
    {
        int handle = iATR(symbol, PERIOD_CURRENT, m_settings.ATR_Period);
        if(handle == INVALID_HANDLE) return -1;

        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(handle, 0, 0, 2, atr) < 2)
        {
            IndicatorRelease(handle);
            return -1;
        }
        IndicatorRelease(handle);
        return atr[1];
    }

    bool IsMarketHealthy(const string symbol, int shift = 0)
    {
        // --- Filtr 1: Keltner Channel Squeeze ---
        if(m_settings.UseKCSqueezeFilter)
        {
            if(!IsInKCSqueeze(symbol, shift))
            {
                // Pokud nejsme ve squeeze (BB jsou roztažené mimo KC), je to bráno jako trend, neobchodujeme.
                return false; 
            }
        }
    
        // --- Filtr 2: ADX síla trendu ---
        if(m_settings.UseAdxTrendFilter)
        {
            double adx_value = GetAdxValue(symbol, shift);
            if(adx_value > m_settings.MaxAdxForEntry || adx_value == -1)
            {
                // Pokud je ADX příliš vysoký (silný trend), neobchodujeme.
                return false;
            }
        }

        return true;
    }

    // NOVÁ FUNKCE: Prediktivní detekce blížícího se konce konsolidace
    bool IsConsolidationWeakening(const string symbol)
    {
        // Kontrola napříč více svíčkami - trendy se obvykle vyvíjejí postupně
        
        // 1. ADX roste rychle = blížící se trend
        if(m_settings.UseAdxTrendFilter)
        {
            double adx_current = GetAdxValue(symbol, 1);   // Aktuální uzavřená svíčka
            double adx_prev = GetAdxValue(symbol, 2);      // Předchozí svíčka
            double adx_prev2 = GetAdxValue(symbol, 3);     // Ještě starší
            
            if(adx_current > 0 && adx_prev > 0 && adx_prev2 > 0)
            {
                // ADX roste 2 svíčky za sebou + blíží se k limitu
                bool adx_rising = (adx_current > adx_prev) && (adx_prev > adx_prev2);
                    double threshold_ratio = 0.60; // 60% max ADX limitu - dřívější varování
                bool approaching_limit = adx_current > (m_settings.MaxAdxForEntry * threshold_ratio);
                
                if(adx_rising && approaching_limit)
                {
                    return true; // Konsolidace slábne - blíží se trend
                }
            }
        }
        
        // 2. Bollinger Bands se rozšiřují = zvyšující se volatilita
        if(m_settings.UseKCSqueezeFilter)
        {
            double bb_width_current = GetBbWidthPercent(symbol, 1);
            double bb_width_prev = GetBbWidthPercent(symbol, 2);
            double bb_width_prev2 = GetBbWidthPercent(symbol, 3);
            
            if(bb_width_current > 0 && bb_width_prev > 0 && bb_width_prev2 > 0)
            {
                // BB šířka roste 2 svíčky za sebou = růst volatility
                bool bb_expanding = (bb_width_current > bb_width_prev * 1.1) && 
                                   (bb_width_prev > bb_width_prev2 * 1.1);
                                   
                if(bb_expanding)
                {
                    return true; // Volatilita roste - konsolidace může končit
                }
            }
        }
        
        return false; // Konsolidace se zdá stabilní
    }

private:

    // Přesunuto do public sekce

    bool ConfirmWithBollingerBands(const string symbol, ENUM_SIGNAL_DIRECTION direction)
    {
        int handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) 
        {
            m_logger.LogInfo("🔍 " + symbol + " - BB handle INVALID");
            return false;
        }

        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);

        if(CopyBuffer(handle, 1, 0, 3, upper) < 3 || CopyBuffer(handle, 2, 0, 3, lower) < 3)
        {
            m_logger.LogInfo("🔍 " + symbol + " - BB CopyBuffer failed");
            IndicatorRelease(handle);
            return false;
        }
        IndicatorRelease(handle);

        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 3, rates) < 3) 
        {
            m_logger.LogInfo("🔍 " + symbol + " - BB CopyRates failed");
            return false;
        }

        // Získat aktuální cenu pro porovnání
        double current_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double current_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        if(direction == SIGNAL_BUY)
        {
            // Pro BUY: kontrola s malou tolerancí pro scalping (0.05%)
            double tolerance = lower[0] * 0.0005; // 0.05% tolerance
            bool confirmed = (current_ask <= lower[0] + tolerance);
            if(confirmed) return true;
        }
        else if(direction == SIGNAL_SELL)
        {
            // Pro SELL: kontrola s malou tolerancí pro scalping (0.05%)
            double tolerance = upper[0] * 0.0005; // 0.05% tolerance
            bool confirmed = (current_bid >= upper[0] - tolerance);
            if(confirmed) return true;
        }
        
        return false;
    }

    bool ConfirmWithBBSlope(const string symbol, ENUM_SIGNAL_DIRECTION direction)
    {
        // Získat handle pro BB
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE)
        {
            return true; // Pokud nelze získat BB, neblokujeme signál
        }
        
        double middle_buffer[];
        ArraySetAsSeries(middle_buffer, true);
        
        // Potřebujeme alespoň 3 hodnoty pro výpočet sklonu
        if(CopyBuffer(bb_handle, 0, 0, 3, middle_buffer) < 3)
        {
            IndicatorRelease(bb_handle);
            return true; // Pokud nelze získat data, neblokujeme signál
        }
        
        IndicatorRelease(bb_handle);
        
        // Výpočet sklonu: aktuální vs předchozí hodnota
        double slope = middle_buffer[0] - middle_buffer[1];
        
        // Threshold pro "významný" sklon (v bodech) - z inputů
        double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        {
            pip_value *= 10; // Pro 5-digit a 3-digit brokery
        }
        double threshold = m_settings.BB_Slope_Threshold_Pips * pip_value;
        
        // Kontrola souladu signálu se sklonem
        if(direction == SIGNAL_BUY && slope < -threshold)
        {
            return false; // BUY signál, ale BB klesá → ODMÍTNOUT
        }
        
        if(direction == SIGNAL_SELL && slope > threshold)
        {
            return false; // SELL signál, ale BB roste → ODMÍTNOUT
        }
        
        return true; // Signál je v souladu se sklonem BB
    }
    
public:
    
    // Public metoda pro Engine
    bool IsBBExpanding(const string symbol)
    {
        // Získat BB pro současnost a 5 svíček zpět
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return false;
        
        double upper_buffer[], lower_buffer[];
        ArraySetAsSeries(upper_buffer, true);
        ArraySetAsSeries(lower_buffer, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 6, upper_buffer) < 6 ||
           CopyBuffer(bb_handle, 2, 0, 6, lower_buffer) < 6)
        {
            IndicatorRelease(bb_handle);
            return false;
        }
        
        // Vypočítat šířku BB nyní vs před 5 svíčkami
        double current_width = upper_buffer[0] - lower_buffer[0];
        double past_width = upper_buffer[5] - lower_buffer[5];
        
        IndicatorRelease(bb_handle);
        
        if(past_width <= 0) return false;
        
        double expansion_ratio = current_width / past_width;
        
        // BB se rozšiřuje pokud je ratio > threshold
        return (expansion_ratio > m_settings.BBExpansionThreshold);
    }

    //------------------------------------------------------------------
    // PŮVODNĚ PRIVÁTNÍ METODY, nyní veřejné pro snazší přístup
    //------------------------------------------------------------------

    
    double GetBbWidthPercent(const string symbol)
    {
        return GetBbWidthPercent(symbol, 1); // Výchozí shift = 1
    }
    
    double GetBbWidthPercent(const string symbol, int shift)
    {
        int handle = iBands(symbol, PERIOD_CURRENT, m_settings.BB_Period, 0, m_settings.BB_Deviation, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return -1;
        
        int bars_needed = shift + 1;
        double middle[], upper[], lower[];
        ArraySetAsSeries(middle, true);
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        if(CopyBuffer(handle, 0, 0, bars_needed, middle) < bars_needed || 
           CopyBuffer(handle, 1, 0, bars_needed, upper) < bars_needed || 
           CopyBuffer(handle, 2, 0, bars_needed, lower) < bars_needed || 
           middle[shift] == 0)
        {
            IndicatorRelease(handle);
            return -1;
        }
        IndicatorRelease(handle);
        
        return (upper[shift] - lower[shift]) / middle[shift] * 100.0;
    }
    
    double GetAtrPercent(const string symbol)
    {
        int handle = iATR(symbol, PERIOD_CURRENT, m_settings.ATR_Period);
        if(handle == INVALID_HANDLE) return -1;

        double atr[], close[];
        ArraySetAsSeries(atr, true);
        ArraySetAsSeries(close, true);
        if(CopyBuffer(handle, 0, 0, 2, atr) < 2 || CopyClose(symbol, PERIOD_CURRENT, 0, 2, close) < 2 || close[1] == 0)
        {
            IndicatorRelease(handle);
            return -1;
        }
        IndicatorRelease(handle);

        return (atr[1] / close[1]) * 100.0;
    }
    
    bool IsInKCSqueeze(const string symbol, int shift = 0)
    {
        // 1. Získání Bollingerových Pásem
        int bb_handle = iBands(symbol, PERIOD_CURRENT, m_settings.BB_Period, 0, m_settings.BB_Deviation, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return false;

        double bb_upper[], bb_lower[];
        ArraySetAsSeries(bb_upper, true);
        ArraySetAsSeries(bb_lower, true);

        if(CopyBuffer(bb_handle, 1, shift, 2, bb_upper) < 2 || CopyBuffer(bb_handle, 2, shift, 2, bb_lower) < 2)
        {
            IndicatorRelease(bb_handle);
            return false;
        }
        IndicatorRelease(bb_handle);

        // 2. Získání ATR (pro Keltnerův kanál)
        int atr_handle = iATR(symbol, PERIOD_CURRENT, m_settings.KC_MAPeriod);
        if(atr_handle == INVALID_HANDLE) return false;

        double atr_buffer[];
        ArraySetAsSeries(atr_buffer, true);
        if(CopyBuffer(atr_handle, 0, shift, 2, atr_buffer) < 2)
        {
            IndicatorRelease(atr_handle);
            return false;
        }
        IndicatorRelease(atr_handle);

        // 3. Získání středové linie pro KC (EMA)
        int ma_handle = iMA(symbol, PERIOD_CURRENT, m_settings.KC_Period, 0, (ENUM_MA_METHOD)m_settings.KC_MAType, PRICE_CLOSE);
        if(ma_handle == INVALID_HANDLE) return false;

        double ma_buffer[];
        ArraySetAsSeries(ma_buffer, true);
        if(CopyBuffer(ma_handle, 0, shift, 2, ma_buffer) < 2)
        {
            IndicatorRelease(ma_handle);
            return false;
        }
        IndicatorRelease(ma_handle);

        // 4. Výpočet Keltnerova kanálu
        double kc_upper = ma_buffer[0] + (atr_buffer[0] * m_settings.KC_Multiplier);
        double kc_lower = ma_buffer[0] - (atr_buffer[0] * m_settings.KC_Multiplier);

        // 5. Porovnání - jsou BB uvnitř KC?
        // Squeeze je aktivní, pokud horní BB je pod horním KC A zároveň spodní BB je nad spodním KC.
        if(bb_upper[0] < kc_upper && bb_lower[0] > kc_lower)
        {
            return true; // Ano, jsme ve squeeze, trh je vhodný pro konsolidační strategii.
        }

        return false; // Ne, nejsme ve squeeze.
    }
    
    double GetAdxValue(const string symbol, int shift = 0)
    {
        int handle = iADX(symbol, PERIOD_CURRENT, m_settings.ADX_Period);
        if(handle == INVALID_HANDLE) return -1;
        
        double adx[];
        ArraySetAsSeries(adx, true);
        if(CopyBuffer(handle, 0, shift, 2, adx) < 2)
        {
             IndicatorRelease(handle);
             return -1;
        }
        IndicatorRelease(handle);
        
        return adx[0];
    }

private:
    double NormalizeScore(double value, double min_val, double max_val, double max_score, bool invert = false)
    {
        if(invert)
        {
            if(value <= min_val) return max_score;
            if(value >= max_val) return 0.0;
            return (1.0 - (value - min_val) / (max_val - min_val)) * max_score;
        }
        else
        {
            if(value >= max_val) return max_score;
            if(value <= min_val) return 0.0;
            return ((value - min_val) / (max_val - min_val)) * max_score;
        }
    }

    double GetRsiScore(const string symbol, double max_score)
    {
        double rsi_val = GetRsiValue(symbol);
        if(rsi_val == -1) return 0.0;

        if(rsi_val > m_settings.RSI_Prekoupeno)
            return NormalizeScore(rsi_val, m_settings.RSI_Prekoupeno, m_settings.Score_RSI_Top, max_score);
        if(rsi_val < m_settings.RSI_Prepredano)
            return NormalizeScore(rsi_val, 0.0, m_settings.RSI_Prepredano, max_score, true);

        return 0.0;
    }
    
    double GetBbScore(const string symbol, double max_score)
    {
        double width_percent = GetBbWidthPercent(symbol);
        if(width_percent == -1) return 0.0;
        return NormalizeScore(width_percent, m_settings.Score_BB_Ideal, m_settings.Score_BB_Top, max_score, true);
    }
    
    double GetAtrScore(const string symbol, double max_score)
    {
        double atr_percent = GetAtrPercent(symbol);
        if(atr_percent == -1) return 0.0;
        return NormalizeScore(atr_percent, m_settings.Score_ATR_Ideal, m_settings.Score_ATR_Top, max_score, true);
    }
    
    double GetAdxScore(const string symbol, double max_score)
    {
        double adx_val = GetAdxValue(symbol);
        if(adx_val == -1) return 0.0;
        return NormalizeScore(adx_val, m_settings.Score_ADX_Ideal, m_settings.Score_ADX_Top, max_score, true);
    }

    //+------------------------------------------------------------------+
    //| UNIFIKOVANÉ SKÓROVÁNÍ PRO OBĚ STRATEGIE                          |
    //+------------------------------------------------------------------+
    double GetUnifiedSymbolScore(const string symbol)
    {
        // UNIFIKOVANÉ SKÓROVÁNÍ: 0-100
        // 0-40: Trendové příležitosti (nízké skóre = silný trend)
        // 40-80: Neutrální/nejasné podmínky
        // 80-100: Konsolidační příležitosti (vysoké skóre = silná konsolidace)
        
        double total_score = 0;
        int active_modules = 0;
        
        // Použít nastavení z m_settings
        if(m_settings.Pouzit_BB_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_ATR_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_ADX_Pro_Skore) active_modules++;
        if(m_settings.Pouzit_RSI_Pro_Skore) active_modules++;
        
        if(active_modules == 0) return 50.0; // Neutrální skóre
        
        double module_weight = 100.0 / active_modules;
        
        if(m_settings.Pouzit_BB_Pro_Skore) 
            total_score += GetUnifiedBBScore(symbol, module_weight);
        if(m_settings.Pouzit_ATR_Pro_Skore) 
            total_score += GetUnifiedATRScore(symbol, module_weight);
        if(m_settings.Pouzit_ADX_Pro_Skore) 
            total_score += GetUnifiedADXScore(symbol, module_weight);
        if(m_settings.Pouzit_RSI_Pro_Skore) 
            total_score += GetUnifiedRSIScore(symbol, module_weight);
        
        return total_score;
    }
    
    double GetUnifiedBBScore(const string symbol, double weight)
    {
        // BB SKÓRE: Široké pásma = nízké skóre (trend), úzké = vysoké (konsolidace)
        int bb_handle = iBands(symbol, PERIOD_CURRENT, m_settings.BB_Period, 0, m_settings.BB_Deviation, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return weight * 0.5; // Neutrální
        
        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 3, upper) < 3 ||
           CopyBuffer(bb_handle, 2, 0, 3, lower) < 3)
        {
            IndicatorRelease(bb_handle);
            return weight * 0.5;
        }
        
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double bb_width = (upper[0] - lower[0]) / current_price * 100.0;
        
        IndicatorRelease(bb_handle);
        
        // UNIFIKOVANÉ SKÓROVÁNÍ:
        if(bb_width >= 0.35) return 0.0;           // Velmi široké = trend (nízké skóre)
        if(bb_width >= 0.25) return weight * 0.2;  // Široké = slabý trend
        if(bb_width >= 0.15) return weight * 0.6;  // Střední = neutrální
        return weight;                              // Úzké = konsolidace (vysoké skóre)
    }
    
    double GetUnifiedATRScore(const string symbol, double weight)
    {
        // ATR SKÓRE: Vysoká volatilita = nízké skóre (trend), nízká = vysoké (konsolidace)
        int atr_handle = iATR(symbol, PERIOD_CURRENT, m_settings.ATR_Period);
        if(atr_handle == INVALID_HANDLE) return weight * 0.5;
        
        double atr[];
        ArraySetAsSeries(atr, true);
        
        if(CopyBuffer(atr_handle, 0, 0, 3, atr) < 3)
        {
            IndicatorRelease(atr_handle);
            return weight * 0.5;
        }
        
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double atr_pct = atr[0] / current_price * 100.0;
        
        IndicatorRelease(atr_handle);
        
        // UNIFIKOVANÉ SKÓROVÁNÍ:
        if(atr_pct >= 0.20) return 0.0;           // Velmi vysoká = trend (nízké skóre)
        if(atr_pct >= 0.13) return weight * 0.3;  // Vysoká = slabý trend
        if(atr_pct >= 0.07) return weight * 0.7;  // Střední = neutrální
        return weight;                             // Nízká = konsolidace (vysoké skóre)
    }
    
    double GetUnifiedADXScore(const string symbol, double weight)
    {
        // ADX SKÓRE: Vysoký ADX = nízké skóre (trend), nízký = vysoké (konsolidace)
        int adx_handle = iADX(symbol, PERIOD_CURRENT, m_settings.ADX_Period);
        if(adx_handle == INVALID_HANDLE) return weight * 0.5;
        
        double adx[];
        ArraySetAsSeries(adx, true);
        
        if(CopyBuffer(adx_handle, 0, 0, 3, adx) < 3)
        {
            IndicatorRelease(adx_handle);
            return weight * 0.5;
        }
        
        double current_adx = adx[0];
        
        IndicatorRelease(adx_handle);
        
        // UNIFIKOVANÉ SKÓROVÁNÍ:
        if(current_adx >= 35.0) return 0.0;        // Velmi vysoký = trend (nízké skóre)
        if(current_adx >= 28.0) return weight * 0.2; // Vysoký = slabý trend
        if(current_adx >= 18.0) return weight * 0.6; // Střední = neutrální
        return weight;                              // Nízký = konsolidace (vysoké skóre)
    }
    
    double GetUnifiedRSIScore(const string symbol, double weight)
    {
        // RSI SKÓRE: Extrémní hodnoty = nízké skóre (trend), střední = vysoké (konsolidace)
        int rsi_handle = iRSI(symbol, PERIOD_CURRENT, m_settings.RSI_Period, PRICE_CLOSE);
        if(rsi_handle == INVALID_HANDLE) return weight * 0.5;
        
        double rsi[];
        ArraySetAsSeries(rsi, true);
        
        if(CopyBuffer(rsi_handle, 0, 0, 3, rsi) < 3)
        {
            IndicatorRelease(rsi_handle);
            return weight * 0.5;
        }
        
        double current_rsi = rsi[0];
        
        IndicatorRelease(rsi_handle);
        
        // UNIFIKOVANÉ SKÓROVÁNÍ:
        if(current_rsi <= 20.0 || current_rsi >= 80.0) return 0.0;        // Extrémní = trend (nízké skóre)
        if(current_rsi <= 25.0 || current_rsi >= 75.0) return weight * 0.3; // Blízko extrému = slabý trend
        if(current_rsi <= 35.0 || current_rsi >= 65.0) return weight * 0.7; // Střední = neutrální
        return weight;                                                      // 35-65 = konsolidace (vysoké skóre)
    }
    
    //+------------------------------------------------------------------+
    //| STRATEGIE ROZLIŠENÍ NA ZÁKLADĚ SKÓRE                              |
    //+------------------------------------------------------------------+
    ENUM_SIGNAL_DIRECTION GetStrategySignal(const string symbol, double score)
    {
        // ROZLIŠENÍ STRATEGIE NA ZÁKLADĚ SKÓRE:
        // Score 0-40: Trendová strategie
        // Score 80-100: Konsolidační strategie
        // Score 40-80: Žádná strategie
        
        if(score <= 40.0)
        {
            // TRENDOVÁ STRATEGIE: Nízké skóre = silný trend
            return GetTrendSignal(symbol);
        }
        else if(score >= 80.0)
        {
            // KONSOLIDAČNÍ STRATEGIE: Vysoké skóre = silná konsolidace
            return GetConsolidationSignal(symbol);
        }
        
        return SIGNAL_NONE; // Neutrální podmínky
    }
    
    ENUM_SIGNAL_DIRECTION GetTrendSignal(const string symbol)
    {
        // TRENDOVÝ SIGNÁL: BB breakout + EMA směr + Stochastic momentum
        
        // 1. Získat BB hranice
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return SIGNAL_NONE;
        
        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 3, upper) < 3 ||
           CopyBuffer(bb_handle, 2, 0, 3, lower) < 3)
        {
            IndicatorRelease(bb_handle);
            return SIGNAL_NONE;
        }
        
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double bb_upper = upper[0];
        double bb_lower = lower[0];
        
        IndicatorRelease(bb_handle);
        
        // 2. Získat EMA pro směr trendu
        int ema_handle = iMA(symbol, PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
        if(ema_handle == INVALID_HANDLE) return SIGNAL_NONE;
        
        double ema[];
        ArraySetAsSeries(ema, true);
        
        if(CopyBuffer(ema_handle, 0, 0, 3, ema) < 3)
        {
            IndicatorRelease(ema_handle);
            return SIGNAL_NONE;
        }
        
        double current_ema = ema[0];
        double prev_ema = ema[1];
        bool ema_rising = current_ema > prev_ema;
        bool ema_falling = current_ema < prev_ema;
        
        IndicatorRelease(ema_handle);
        
        // 3. Získat Stochastic
        int stoch_handle = iStochastic(symbol, PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
        if(stoch_handle == INVALID_HANDLE) return SIGNAL_NONE;
        
        double stoch[];
        ArraySetAsSeries(stoch, true);
        
        if(CopyBuffer(stoch_handle, 0, 0, 3, stoch) < 3)
        {
            IndicatorRelease(stoch_handle);
            return SIGNAL_NONE;
        }
        
        double current_stoch = stoch[0];
        IndicatorRelease(stoch_handle);
        
        // 4. TRENDOVÁ LOGIKA: Breakout + EMA směr + Stochastic momentum
        
        // BUY TREND: BB breakout nahoru + EMA roste + cena nad EMA + Stochastic momentum
        if(current_price >= bb_upper * 0.999 && 
           current_price > current_ema && 
           ema_rising &&
           current_stoch >= 20.0 && current_stoch <= 80.0)
        {
            return SIGNAL_BUY;
        }
        
        // SELL TREND: BB breakout dolů + EMA klesá + cena pod EMA + Stochastic momentum
        if(current_price <= bb_lower * 1.001 && 
           current_price < current_ema && 
           ema_falling &&
           current_stoch >= 20.0 && current_stoch <= 80.0)
        {
            return SIGNAL_SELL;
        }
        
        return SIGNAL_NONE;
    }
    
    ENUM_SIGNAL_DIRECTION GetConsolidationSignal(const string symbol)
    {
        // KONSOLIDAČNÍ SIGNÁL: Použít existující logiku
        return GetCombinedSignal(symbol);
    }


};
