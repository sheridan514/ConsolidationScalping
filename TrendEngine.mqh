//+------------------------------------------------------------------+
//|                                                   TrendEngine.mqh |
//|                        Copyright 2024, Investwisdom             |
//|                                    https://www.investwisdom.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Investwisdom"
#property link      "https://www.investwisdom.cz"

#include "Settings.mqh"
#include "Logger.mqh"
#include "TradeManager.mqh"

//+------------------------------------------------------------------+
//| Engine optimalizovaný pro trendovou strategii                    |
//+------------------------------------------------------------------+
class CTrendEngine
{
private:
    SSettings m_settings;
    CLogger m_logger;
    CTradeManager m_tradeManager;
    
    string m_symbols[];
    int m_total_symbols;
    
    // === TRENDOVÉ SKÓROVÁNÍ ===
    datetime m_last_scan_time;
    datetime m_last_debug_time;

public:
    CTrendEngine() : m_total_symbols(0), m_last_scan_time(0), m_last_debug_time(0) {}
    ~CTrendEngine() {}

    bool Initialize(const SSettings &settings)
    {
        m_settings = settings;
        
        m_logger.Initialize();
        
        m_tradeManager.Initialize(&m_logger, m_settings.Scalping_MagicNumber);
        

        
        // Parsovat symboly pro obchodování
        if(!ParseSymbols())
        {
            m_logger.LogError("CTrendEngine: Chyba při parsování symbolů");
            return false;
        }
        
        Print("✅ TrendEngine inicializován s " + IntegerToString(m_total_symbols) + " symboly");
        return true;
    }
    
    void Deinitialize(const int reason)
    {
        // Cleanup
        m_logger.LogInfo("TrendEngine deinicializován, důvod: " + IntegerToString(reason));
    }
    
    // === GETTERY ===
    CTradeManager* GetTradeManager() { return &m_tradeManager; }
    CLogger* GetLogger() { return &m_logger; }
    

    
    // === HLAVNÍ LOGIKA ===
    void OnTick()
    {
        // Throttling - ne více než každých 5 sekund
        if(TimeCurrent() - m_last_scan_time < 5) return;
        m_last_scan_time = TimeCurrent();
        
        // Trendová logika
        ProcessTrendLogic();
        
        // Správa existujících pozic (trailing)
        ManageTrendPositions();
        

    }
    
    void OnTimer()
    {
        // Timer logika pro trendový systém
        if(TimeCurrent() - m_last_debug_time >= 30)
        {
            Print("🔥 TREND ENGINE: Aktivní, Magic: " + IntegerToString(m_settings.Scalping_MagicNumber));
            m_last_debug_time = TimeCurrent();
        }
        

    }

private:
    //+------------------------------------------------------------------+
    //| PARSOVÁNÍ SYMBOLŮ                                               |
    //+------------------------------------------------------------------+
    bool ParseSymbols()
    {
        string symbols[];
        int symbol_count = StringSplit(m_settings.SymbolsToTrade, ',', symbols);
        
        if(symbol_count <= 0)
        {
            // Fallback na výchozí set
            string fallback[] = {"EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","USDCAD"};
            ArrayCopy(symbols, fallback);
            symbol_count = ArraySize(symbols);
        }
        
        // Kopírovat do member array
        ArrayResize(m_symbols, symbol_count);
        for(int i = 0; i < symbol_count; i++)
        {
            // OPRAVA: StringTrimRight a StringTrimLeft vrací int, ne string
            // Musíme použít StringTrim nebo vlastní implementaci
            string clean_symbol = symbols[i];
            // Oříznout mezery zleva
            while(StringLen(clean_symbol) > 0 && StringGetCharacter(clean_symbol, 0) == ' ')
            {
                clean_symbol = StringSubstr(clean_symbol, 1);
            }
            // Oříznout mezery zprava
            while(StringLen(clean_symbol) > 0 && StringGetCharacter(clean_symbol, StringLen(clean_symbol) - 1) == ' ')
            {
                clean_symbol = StringSubstr(clean_symbol, 0, StringLen(clean_symbol) - 1);
            }
            m_symbols[i] = clean_symbol;
        }
        
        m_total_symbols = symbol_count;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| TRENDOVÁ LOGIKA                                                 |
    //+------------------------------------------------------------------+
    void ProcessTrendLogic()
    {
        // Zkontrolovat počet aktivních trendových pozic
        int current_trend_positions = GetTrendPositionsCount();
        if(current_trend_positions >= m_settings.Scalping_MaxPositions)
        {
            return; // Už máme dost trendových pozic
        }
        
        // Najít nejlepší trendovou příležitost
        string best_symbol = "";
        double lowest_score = 100.0;
        ENUM_POSITION_TYPE best_direction = POSITION_TYPE_BUY;
        
        for(int i = 0; i < m_total_symbols; i++)
        {
            string symbol = m_symbols[i];
            
            // Skip pokud už máme pozici na tomto symbolu
            if(HasTrendPositionForSymbol(symbol)) continue;
            
            // POUŽÍT VLASTNÍ TRENDOVÝ FILTR
            double score = GetTrendSymbolScore(symbol);
            if(score >= m_settings.Scalping_MinScore) continue; // Score musí být nízký pro trend
            
            // Získat trendový signál
            ENUM_SIGNAL_DIRECTION trend_direction = GetTrendMomentumSignal(symbol);
            if(trend_direction == SIGNAL_NONE) continue;
            
            // Ověřit, že jde skutečně o trend
            if(!IsTrendConfirmed(symbol)) continue;
            
            // Vybrat nejlepší kandidát (nejnižší score = největší trend)
            if(score < lowest_score)
            {
                lowest_score = score;
                best_symbol = symbol;
                best_direction = (trend_direction == SIGNAL_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            }
        }
        
        // Otevřít nejlepší trendovou pozici
        if(best_symbol != "")
        {
            Print("🎯 TREND SELECTED: " + best_symbol + " Score:" + DoubleToString(lowest_score, 1) + 
                  " Direction:" + (best_direction == POSITION_TYPE_BUY ? "BUY" : "SELL"));
            OpenTrendPosition(best_symbol, best_direction, lowest_score);
        }
        
        // Debug informace
        if(TimeCurrent() - m_last_debug_time >= 30)
        {
            Print("🔥 TREND SCANNER: Active " + IntegerToString(current_trend_positions) + "/" + 
                  IntegerToString(m_settings.Scalping_MaxPositions) + 
                  (best_symbol != "" ? ", OPENING: " + best_symbol : ", No opportunities"));
            m_last_debug_time = TimeCurrent();
        }
    }
    
    //+------------------------------------------------------------------+
    //| TRENDOVÉ SKÓROVÁNÍ - NEZÁVISLÉ NA ENGINE                      |
    //+------------------------------------------------------------------+
    double GetTrendSymbolScore(const string symbol)
    {
        double total_score = 0;
        int active_modules = 0;
        
        // Použít trendové parametry
        bool use_bb = true;    // BB expansion pro trendy
        bool use_atr = true;   // ATR růst pro trendy  
        bool use_adx = true;   // ADX růst pro trendy
        
        if(use_bb) active_modules++;
        if(use_atr) active_modules++;
        if(use_adx) active_modules++;
        
        if(active_modules == 0) return 100.0;
        
        double module_weight = 100.0 / active_modules;
        
        if(use_bb) total_score += GetTrendBBScore(symbol, module_weight);
        if(use_atr) total_score += GetTrendATRScore(symbol, module_weight);
        if(use_adx) total_score += GetTrendADXScore(symbol, module_weight);
        
        return total_score;
    }
    
    double GetTrendBBScore(const string symbol, double weight)
    {
        // BB SCORE PRO TRENDY: Široké pásma = nízké skóre (trend)
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) return weight; // Neutrální skóre
        
        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 3, upper) < 3 ||
           CopyBuffer(bb_handle, 2, 0, 3, lower) < 3)
        {
            IndicatorRelease(bb_handle);
            return weight;
        }
        
        // Výpočet šířky BB v procentech
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double bb_width = (upper[0] - lower[0]) / current_price * 100.0;
        
        IndicatorRelease(bb_handle);
        
        // TRENDOVÉ SKÓROVÁNÍ: Široké BB = nízké skóre
        if(bb_width >= 0.35) return 0.0;           // Velmi široké = trend
        if(bb_width >= 0.25) return weight * 0.2;  // Široké = slabý trend
        if(bb_width >= 0.15) return weight * 0.6;  // Střední = konsolidace
        return weight;                              // Úzké = silná konsolidace
    }
    
    double GetTrendATRScore(const string symbol, double weight)
    {
        // ATR SCORE PRO TRENDY: Vysoká volatilita = nízké skóre (trend)
        int atr_handle = iATR(symbol, PERIOD_CURRENT, 14);
        if(atr_handle == INVALID_HANDLE) return weight;
        
        double atr[];
        ArraySetAsSeries(atr, true);
        
        if(CopyBuffer(atr_handle, 0, 0, 3, atr) < 3)
        {
            IndicatorRelease(atr_handle);
            return weight;
        }
        
        double current_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double atr_pct = atr[0] / current_price * 100.0;
        
        IndicatorRelease(atr_handle);
        
        // TRENDOVÉ SKÓROVÁNÍ: Vysoká ATR = nízké skóre
        if(atr_pct >= 0.20) return 0.0;           // Velmi vysoká = trend
        if(atr_pct >= 0.13) return weight * 0.3;  // Vysoká = slabý trend
        if(atr_pct >= 0.07) return weight * 0.7;  // Střední = konsolidace
        return weight;                             // Nízká = silná konsolidace
    }
    
    double GetTrendADXScore(const string symbol, double weight)
    {
        // ADX SCORE PRO TRENDY: Vysoký ADX = nízké skóre (trend)
        int adx_handle = iADX(symbol, PERIOD_CURRENT, 14);
        if(adx_handle == INVALID_HANDLE) return weight;
        
        double adx[];
        ArraySetAsSeries(adx, true);
        
        if(CopyBuffer(adx_handle, 0, 0, 3, adx) < 3)
        {
            IndicatorRelease(adx_handle);
            return weight;
        }
        
        double current_adx = adx[0];
        
        IndicatorRelease(adx_handle);
        
        // TRENDOVÉ SKÓROVÁNÍ: Vysoký ADX = nízké skóre
        if(current_adx >= 35.0) return 0.0;        // Velmi vysoký = trend
        if(current_adx >= 28.0) return weight * 0.2; // Vysoký = slabý trend
        if(current_adx >= 18.0) return weight * 0.6; // Střední = konsolidace
        return weight;                              // Nízký = silná konsolidace
    }
    
    //+------------------------------------------------------------------+
    //| TRENDOVÉ SIGNÁLY A POTVRZENÍ                                    |
    //+------------------------------------------------------------------+
    ENUM_SIGNAL_DIRECTION GetTrendMomentumSignal(const string symbol)
    {
        // TRENDOVÝ SIGNÁL = Trend podmínky + Direction
        
        // 1. Zkontrolovat trend podmínky
        if(!IsTrendConditionsMet(symbol)) return SIGNAL_NONE;
        
        // 2. Získat směr
        return GetTrendDirection(symbol);
    }
    
    bool IsTrendConditionsMet(const string symbol)
    {
        // TREND PODMÍNKY: BB expansion + ADX růst + ATR růst
        
        if(!CheckBBExpansion(symbol)) return false;
        if(!CheckADXRising(symbol)) return false; 
        if(!CheckATRRising(symbol)) return false;
        
        return true;
    }
    
    ENUM_SIGNAL_DIRECTION GetTrendDirection(const string symbol)
    {
        // TRENDOVÝ SMĚR: BB breakout + EMA směr + Stochastic momentum
        
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
    
    bool IsTrendConfirmed(const string symbol)
    {
        // Kombinuje všechny trend potvrzovací faktory
        return CheckBBExpansion(symbol) && 
               CheckADXRising(symbol) && 
               CheckATRRising(symbol);
    }
    
    bool CheckBBExpansion(const string symbol)
    {
        // BB EXPANSION: width[1] > width[2,3,4,5]
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
        
        // Spočítat šířky BB pásem
        double width[6];
        for(int i = 0; i < 6; i++)
        {
            width[i] = upper_buffer[i] - lower_buffer[i];
        }
        
        IndicatorRelease(bb_handle);
        
        // width[1] > width[2] && width[1] > width[3] && width[1] > width[4] && width[1] > width[5]
        bool expansion = (width[1] > width[2]) && 
                        (width[1] > width[3]) && 
                        (width[1] > width[4]) && 
                        (width[1] > width[5]);
        
        return expansion;
    }
    
    bool CheckADXRising(const string symbol)
    {
        // ADX RŮST: adx[1] > adx[2] 
        int adx_handle = iADX(symbol, PERIOD_CURRENT, 14);
        if(adx_handle == INVALID_HANDLE) return false;
        
        double adx_buffer[];
        ArraySetAsSeries(adx_buffer, true);
        
        if(CopyBuffer(adx_handle, 0, 0, 3, adx_buffer) < 3)
        {
            IndicatorRelease(adx_handle);
            return false;
        }
        
        // adx[1] > adx[2] = ADX roste
        bool adx_rising = (adx_buffer[1] > adx_buffer[2]);
        
        IndicatorRelease(adx_handle);
        
        return adx_rising;
    }
    
    bool CheckATRRising(const string symbol)
    {
        // ATR RŮST: atr[1] > atr[2]
        int atr_handle = iATR(symbol, PERIOD_CURRENT, 14);
        if(atr_handle == INVALID_HANDLE) return false;
        
        double atr_buffer[];
        ArraySetAsSeries(atr_buffer, true);
        
        if(CopyBuffer(atr_handle, 0, 0, 3, atr_buffer) < 3)
        {
            IndicatorRelease(atr_handle);
            return false;
        }
        
        // atr[1] > atr[2] = ATR roste
        bool atr_rising = (atr_buffer[1] > atr_buffer[2]);
        
        IndicatorRelease(atr_handle);
        
        return atr_rising;
    }
    
    //+------------------------------------------------------------------+
    //| POZICE A TRADING                                                |
    //+------------------------------------------------------------------+
    void OpenTrendPosition(string symbol, ENUM_POSITION_TYPE direction, double score)
    {
        // PŘÍMÉ VOLÁNÍ OrderSend - úplně obejít Engine/TradeManager auto-TP logiku!
        
        // Vypočítat parametry
        double lot_size = m_settings.Scalping_FixedLot;
        double price = (direction == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
        
        // Vypočítat SL (z inputů místo fixních hodnot)
        double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
            
        // Použít SL parametr z settings
        double sl_pips = (double)m_settings.Scalping_SLPips;
        
        double sl_price;
        if(direction == POSITION_TYPE_BUY)
            sl_price = price - (sl_pips * pip_value); // Správný SL
        else
            sl_price = price + (sl_pips * pip_value);
        
        string comment = "Trend_Trade_" + (direction == POSITION_TYPE_BUY ? "BUY" : "SELL");
        ENUM_ORDER_TYPE order_type = (direction == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        
        // PŘÍMÝ OrderSend - ŽÁDNÉ AUTO-TP!
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = symbol;
        request.volume = lot_size;
        request.type = order_type;
        request.price = price;
        request.sl = sl_price;
        request.tp = 0;  // GARANTOVANO ŽÁDNÉ TP!
        request.magic = m_settings.Scalping_MagicNumber;
        request.comment = comment;
        request.type_filling = ORDER_FILLING_FOK;
        
        bool order_result = OrderSend(request, result);
        if(order_result && result.retcode == TRADE_RETCODE_DONE)
        {
            Print("🚀 TREND OPENED: " + symbol + " " + 
                  (direction == POSITION_TYPE_BUY ? "BUY" : "SELL") + 
                  " " + DoubleToString(lot_size, 3) + " lots, Score:" + DoubleToString(score, 1) +
                  " Magic:" + IntegerToString(m_settings.Scalping_MagicNumber) + 
                  " SL:" + DoubleToString(sl_price, 5) + " TP:NONE");
        }
        else
        {
            Print("❌ TREND FAILED: " + symbol + " Error:" + IntegerToString(result.retcode));
        }
    }
    
    int GetTrendPositionsCount()
    {
        int count = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.Scalping_MagicNumber) continue;
            
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "Trend_Trade") >= 0) count++;
        }
        return count;
    }
    
    bool HasTrendPositionForSymbol(string symbol)
    {
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.Scalping_MagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
            
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "Trend_Trade") >= 0) return true;
        }
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| SPRÁVA EXISTUJÍCÍCH POZIC (TRAILING)                            |
    //+------------------------------------------------------------------+
    void ManageTrendPositions()
    {
        // JEDNODUCHÉ TRAILING - žádná komplexní detekce konce trendu!
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.Scalping_MagicNumber) continue;
            
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "Trend_Trade") < 0) continue; // Jen naše trendové pozice
            
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            
            // DEBUG: Kontrola TP - NEMĚLO by být!
            if(current_tp > 0)
            {
                Print("⚠️ TREND POZICE MÁ TP! " + symbol + " Ticket:" + IntegerToString(ticket) + 
                      " Magic:" + IntegerToString(PositionGetInteger(POSITION_MAGIC)) + 
                      " TP:" + DoubleToString(current_tp, 5) + " - ODSTRAŇUJI!");
                      
                // Okamžitě odstranit TP
                MqlTradeRequest remove_tp = {};
                MqlTradeResult remove_result = {};
                
                remove_tp.action = TRADE_ACTION_SLTP;
                remove_tp.position = ticket;
                remove_tp.symbol = symbol;
                remove_tp.sl = current_sl;
                remove_tp.tp = 0; // Odstranit TP
                
                bool order_result = OrderSend(remove_tp, remove_result);
                if(order_result && remove_result.retcode == TRADE_RETCODE_DONE)
                {
                    Print("✅ TP ODSTRANĚNO: " + symbol);
                }
                else
                {
                    Print("❌ NELZE ODSTRANIT TP: " + symbol + " Error:" + IntegerToString(remove_result.retcode));
                }
            }
            
            // Pouze TRAILING STOP - mechanicky, jednoduše!
            ApplyTrendTrailing(symbol, ticket, pos_type, open_price, current_sl);
        }
    }
    
    void ApplyTrendTrailing(string symbol, ulong ticket, ENUM_POSITION_TYPE pos_type, double open_price, double current_sl)
    {
        // Výpočet současného profitu
        double current_price = (pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
            
        // Výpočet pip value
        double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
            
        double profit_pips = (pos_type == POSITION_TYPE_BUY) ? 
            (current_price - open_price) / pip_value : (open_price - current_price) / pip_value;
            
        // Trailing aktivace po dosažení threshold
        if(profit_pips >= m_settings.Scalping_TrailLockPips)
        {
            double trail_step = m_settings.Scalping_TrailStepPips * pip_value;
            double new_sl;
            
            if(pos_type == POSITION_TYPE_BUY)
            {
                new_sl = current_price - trail_step;
                new_sl = MathMax(new_sl, open_price); // Nikdy pod entry
                
                // Pokud current_sl je 0 (bez SL) nebo new_sl je lepší
                if(current_sl == 0 || new_sl > current_sl)
                {
                    Print("📈 BUY TRAILING: " + symbol + " Profit:" + DoubleToString(profit_pips, 1) + "p, NewSL:" + DoubleToString(new_sl, 5));
                    UpdateTrendSL(symbol, ticket, new_sl);
                }
            }
            else
            {
                new_sl = current_price + trail_step;
                new_sl = MathMin(new_sl, open_price); // Nikdy nad entry
                
                // Pokud current_sl je 0 (bez SL) nebo new_sl je lepší  
                if(current_sl == 0 || new_sl < current_sl)
                {
                    Print("📉 SELL TRAILING: " + symbol + " Profit:" + DoubleToString(profit_pips, 1) + "p, NewSL:" + DoubleToString(new_sl, 5));
                    UpdateTrendSL(symbol, ticket, new_sl);
                }
            }
        }
    }
    
    void UpdateTrendSL(string symbol, ulong ticket, double new_sl)
    {
        // Použít TradeManager pro modifikaci SL - konzistentní přístup!
        CTradeManager* trade_manager = &m_tradeManager;
        if(!trade_manager) return;
        
        // TradeManager nemá modifikaci SL, použijeme přímé volání (pro jednoduchost)
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = new_sl;
        request.tp = 0;
        
        bool order_result = OrderSend(request, result);
        if(order_result && result.retcode == TRADE_RETCODE_DONE)
        {
            Print("📈 TREND TRAIL: " + symbol + " SL→" + DoubleToString(new_sl, 5));
        }
        else
        {
            Print("❌ TREND TRAIL FAILED: " + symbol + " Error:" + IntegerToString(result.retcode));
        }
    }
};
