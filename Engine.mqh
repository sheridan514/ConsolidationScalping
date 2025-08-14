//+------------------------------------------------------------------+
//|                                                       Engine.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include "Settings.mqh"
#include "Logger.mqh"
#include "Filter.mqh"
#include "TradeManager.mqh"
#include "Dashboard.mqh"

//+------------------------------------------------------------------+
//| Hlavní engine pro scalping                                      |
//+------------------------------------------------------------------+
class CEngine
{
private:
    SSettings m_settings;
    CLogger m_logger;
    CFilter m_filter;
    CTradeManager m_tradeManager;
    CDashboard m_dashboard;
    
    string m_symbols[];
    int m_total_symbols;

    // === Mapování pro svíčky ===
    string last_processed_candle_time[];

public:
    CEngine() : m_total_symbols(0) {}
    ~CEngine() {}

    bool Initialize(const SSettings &settings)
    {
        m_settings = settings;
        
        m_logger.Initialize();
        
        if(!m_filter.Initialize(m_settings))
        {
            m_logger.LogError("CEngine: Chyba při inicializaci filtru");
            return false;
        }

        m_tradeManager.Initialize(&m_logger, m_settings.Scalping_MagicNumber);
        
        // Dashboard inicializace bude později po parsování symbolů
        
        // Parsovat symboly pro obchodování
        if(!ParseSymbols())
        {
            m_logger.LogError("CEngine: Chyba při parsování symbolů");
            return false;
        }
        

        
        // Inicializovat dashboard po parsování symbolů
            m_dashboard.Initialize(m_settings, m_symbols);
        
        // Nastavit timer pro vyčištění grafu (jen v visual testeru)
        if(MQLInfoInteger(MQL_VISUAL_MODE))
        {
            EventSetTimer(1);
        }
        
        return true;
    }
    
    CFilter* GetFilter() { return &m_filter; }

    CTradeManager* GetTradeManager() { return &m_tradeManager; }
    CLogger* GetLogger() { return &m_logger; }
    
    bool GetSignalInfoForSymbol(const string symbol, SSignalInfo &info)
    {
        info.symbol = symbol;
        info.score = m_filter.GetSymbolScore(symbol);
        info.final_signal = m_filter.GetCombinedSignal(symbol);
        info.rsi_signal = m_filter.GetRsiSignal(symbol);
        info.bb_signal = m_filter.GetBollingerSignal(symbol);
        info.stoch_signal = m_filter.GetStochasticSignal(symbol);
        info.grid_status = GRID_NONE; // Scalping nepoužívá grid
        return true;
    }

    void Deinitialize(const int reason)
    {

        // Cleanup pokud potřeba
    }

public:
    //+------------------------------------------------------------------+
    //| HLAVNÍ LOGIKA                                                    |
    //+------------------------------------------------------------------+
    void OnTick()
    {
        // DEBUG: Log že OnTick běží
        static datetime last_debug = 0;
        if(TimeCurrent() - last_debug >= 30)
        {
            m_logger.LogInfo("🔄 OnTick: ScalpingEnabled=" + (m_settings.Scalping_Enabled ? "true" : "false"));
            last_debug = TimeCurrent();
        }
        
        if(!m_settings.Scalping_Enabled) 
        {
            // I když je scalping vypnutý, stále zkontrolovat pozice pro management
            ProcessScalpingLogic();
            return;
        }
        
        // Zpracovat scalping logiku
        ProcessScalpingLogic();
        
        // Aktualizovat dashboard pokud je zapnutý
        if(m_settings.ShowDashboard)
        {
            UpdateDashboard();
        }
    }
    
    void OnTimer()
    {
        EventKillTimer();
        RemoveAllSubcharts();
    }
    
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
    {
        // Recovery trading při SL hit
        if(m_settings.RecoveryOnSLHit && 
           trans.type == TRADE_TRANSACTION_DEAL_ADD && 
           trans.deal_type == DEAL_TYPE_SELL &&
           request.magic == m_settings.Scalping_MagicNumber)
        {
            // Zkontrolovat, zda se nejedná o recovery pozici
            if(StringFind(request.comment, "Recovery_Trade") < 0)
            {
                CheckForSLHitRecovery(trans, request);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| HELPER METODY                                                    |
    //+------------------------------------------------------------------+
    int GetOpenScalpingPositionsCount()
    {
        int count = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetInteger(POSITION_MAGIC) == m_settings.Scalping_MagicNumber)
                {
                    count++;
                }
            }
        }
        return count;
    }

    string GetAllSymbols()
    {
        string symbols_list = "";
        for(int i = 0; i < m_total_symbols; i++)
        {
            if(i > 0) symbols_list += ",";
            symbols_list += m_symbols[i];
        }
        return symbols_list;
    }

private:
    
    //+------------------------------------------------------------------+
    //| SCALPING LOGIKA                                                  |
    //+------------------------------------------------------------------+
    void ProcessScalpingLogic()
    {
        // DEBUG: Ověřit že se ProcessScalpingLogic volá
        static datetime last_process_debug = 0;
        if(TimeCurrent() - last_process_debug >= 10) {
            m_logger.LogInfo("🎯 PROCESS SCALPING LOGIC RUNNING");
            last_process_debug = TimeCurrent();
        }
        
        // Trend protection: uzavřít pozice pokud se konsolidace změnila na trend
        if(m_settings.CloseOnTrend)
        {
            CheckTrendProtection();
        }
        
        // Hybridní trailing: monitorovat pozice pro trailing po dosažení TP
        ManageHybridTrailing();
        
        // Hledání nových vstupů
        CheckScalpingEntries();
    }
    
    void CheckTrendProtection()
    {
        // Projít všechny otevřené pozice a zkontrolovat score jejich symbolů
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!PositionSelectByTicket(PositionGetTicket(i)))
                continue;
            
            // Kontrola, zda pozice patří našemu EA
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.Scalping_MagicNumber)
                continue;
                
            string symbol = PositionGetString(POSITION_SYMBOL);
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            
            // Získat aktuální score symbolu
            double current_score = m_filter.GetSymbolScore(symbol);
            
            // Zkontrolovat, zda se nejedná o recovery pozici
            string position_comment = PositionGetString(POSITION_COMMENT);
            bool is_recovery_position = (StringFind(position_comment, "Recovery_Trade") >= 0);
            
            if(!is_recovery_position) // Neaplikovat trend protection na recovery pozice
            {
                // TREND PROTECTION: Tvrdé uzavření při trendu
                if(current_score < m_settings.TrendThreshold)
                {
                    ClosePositionDueToTrend(symbol, ticket, current_score);
                }
                // EARLY WARNING RECOVERY: Softer recovery při warning threshold
                else if(current_score < m_settings.WarningThreshold && m_settings.UseRecoveryTrading)
                {
                    ClosePositionForEarlyWarning(symbol, ticket, current_score);
                }
            }
        }
    }
    
    void ClosePositionDueToTrend(string symbol, ulong ticket, double current_score)
    {
        // === ZAZNAMET INFORMACE PRO RECOVERY ===
        ENUM_POSITION_TYPE closed_pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double closed_volume = PositionGetDouble(POSITION_VOLUME);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double current_price = (closed_pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        // Spočítat ztrátu (v USD)
        double loss_points = (closed_pos_type == POSITION_TYPE_BUY) ? 
            (open_price - current_price) : (current_price - open_price);
        double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double loss_usd = loss_points * point_value * closed_volume;
        

        
        // === UZAVŘÍT PŮVODNÍ POZICI ===
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = symbol;
        request.type_filling = ORDER_FILLING_IOC;
        
        if(closed_pos_type == POSITION_TYPE_BUY)
        {
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
        }
        else
        {
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        }
        
        request.volume = closed_volume;
        request.magic = m_settings.Scalping_MagicNumber;
        request.comment = "Trend_Protection_Close";
        
        if(OrderSend(request, result))
        {

                
            // === SPUSTIT RECOVERY TRADING ===
            if(m_settings.UseRecoveryTrading)
            {
                // Recovery spustíme vždy při trend protection (i při malém zisku)
                // protože účelem je profitovat z detekovaného trendu
                double actual_loss = (loss_usd > 0) ? loss_usd : 0.01; // Minimální "ztráta" pro recovery
                ExecuteRecoveryTrade(symbol, closed_pos_type, actual_loss, current_score, ticket);
            }
        }
        else
        {
            m_logger.LogError("CheckTrendProtection: Failed to close position " + IntegerToString(ticket) + " for " + symbol + ", error: " + IntegerToString(result.retcode));
        }
    }
    
    void ClosePositionForEarlyWarning(string symbol, ulong ticket, double current_score)
    {
        // === ZAZNAMET INFORMACE PRO RECOVERY ===
        ENUM_POSITION_TYPE closed_pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double closed_volume = PositionGetDouble(POSITION_VOLUME);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double current_price = (closed_pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        // Spočítat P&L (může být ztráta nebo zisk)
        double loss_points = (closed_pos_type == POSITION_TYPE_BUY) ? 
            (open_price - current_price) : (current_price - open_price);
        double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double pnl_usd = loss_points * point_value * closed_volume;
        
        // === UZAVŘÍT PŮVODNÍ POZICI ===
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = symbol;
        request.type_filling = ORDER_FILLING_IOC;
        
        if(closed_pos_type == POSITION_TYPE_BUY)
        {
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
                    }
                    else
                    {
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        }
        
        request.volume = closed_volume;
        request.magic = m_settings.Scalping_MagicNumber;
        request.comment = "Early_Warning_Close";
        
        if(OrderSend(request, result))
        {

                
            // === SPUSTIT RECOVERY TRADING ===
            if(m_settings.UseRecoveryTrading)
            {
                double actual_loss = MathMax(MathAbs(pnl_usd), 0.01); // Použít absolutní hodnotu P&L
                ExecuteRecoveryTrade(symbol, closed_pos_type, actual_loss, current_score, ticket);
                    }
                }
                else
                {
            m_logger.LogError("Early Warning: Failed to close position " + IntegerToString(ticket) + " for " + symbol + ", error: " + IntegerToString(result.retcode));
        }
    }
    
    void CheckForSLHitRecovery(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
    {
        // Získat informace o uzavřené pozici
        string symbol = trans.symbol;
        double volume = trans.volume;
        double price = trans.price;
        
        // Zkusit získat historii dealu pro informace o SL/TP
        if(HistoryDealSelect(trans.deal))
        {
            string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            double deal_profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            
            // Pokud je to SL hit (negativní profit a příslušný komentář)
            if(deal_profit < 0 && (StringFind(deal_comment, "sl") >= 0 || StringFind(deal_comment, "stop") >= 0))
            {
                m_logger.LogInfo("🚨 SL HIT DETECTED: " + symbol + " Loss: $" + DoubleToString(deal_profit, 2));
                
                // Určit typ uzavřené pozice
                ENUM_POSITION_TYPE closed_type = (trans.deal_type == DEAL_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
                double current_score = m_filter.GetSymbolScore(symbol);
                
                // Spustit recovery trade
                ExecuteRecoveryTrade(symbol, closed_type, MathAbs(deal_profit), current_score);
            }
        }
    }
    
    void ExecuteRecoveryTrade(string symbol, ENUM_POSITION_TYPE closed_pos_type, double loss_usd, double current_score, ulong original_ticket = 0)
    {
        m_logger.LogInfo("🚀 RECOVERY START: " + symbol + ", ClosedType=" + (closed_pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL") + ", Loss=$" + DoubleToString(loss_usd, 2));
        
        // === URČIT SMĚR RECOVERY POZICE (OPAČNÝ K ZAVŘENÉ) ===
        ENUM_ORDER_TYPE recovery_type;
        ENUM_POSITION_TYPE recovery_pos_type;
        
        if(closed_pos_type == POSITION_TYPE_BUY)
        {
            recovery_type = ORDER_TYPE_SELL; // Trend jde dolů -> SELL recovery
            recovery_pos_type = POSITION_TYPE_SELL;
                    }
                    else
                    {
            recovery_type = ORDER_TYPE_BUY; // Trend jde nahoru -> BUY recovery  
            recovery_pos_type = POSITION_TYPE_BUY;
        }
        
        // === VYPOČÍTAT VELIKOST RECOVERY POZICE ===
        double base_lot = m_settings.Scalping_FixedLot;
        double recovery_lot = base_lot * m_settings.RecoveryLotMultiplier;
        
        // Proper lot size validation
        double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        // Normalize to lot step
        if(lot_step > 0)
        {
            recovery_lot = MathRound(recovery_lot / lot_step) * lot_step;
        }
        
        // Apply min/max limits
        recovery_lot = MathMax(min_lot, MathMin(max_lot, recovery_lot));
        
        m_logger.LogInfo("📊 LOT CALC: Base=" + DoubleToString(base_lot, 2) + 
            ", Multiplier=" + DoubleToString(m_settings.RecoveryLotMultiplier, 2) + 
            ", Final=" + DoubleToString(recovery_lot, 2) + 
            ", Step=" + DoubleToString(lot_step, 2));
        
        // === VYPOČÍTAT TP A SL ===
        double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        {
            pip_value *= 10;
        }
        
        double recovery_sl_distance = m_settings.RecoverySLPips * pip_value;
        
        // === OTEVŘÍT RECOVERY POZICI ===
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = symbol;
        request.volume = recovery_lot;
        request.type = recovery_type;
        request.type_filling = ORDER_FILLING_IOC;
        request.magic = m_settings.Scalping_MagicNumber;
        // Ujistit se, že loss_usd je alespoň 0.01 pro rozumný target
        double effective_loss = MathMax(loss_usd, 0.01);
        request.comment = "Recovery_Trade_#" + IntegerToString(original_ticket) + "_$" + DoubleToString(effective_loss, 2);
        
        m_logger.LogInfo("📝 RECOVERY COMMENT: " + request.comment + " (original_loss=" + DoubleToString(loss_usd, 2) + ")");
        
        if(recovery_pos_type == POSITION_TYPE_BUY)
        {
            request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            request.tp = 0; // BEZ TP - použijeme trailing
            request.sl = request.price - recovery_sl_distance;
            }
            else
            {
            request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
            request.tp = 0; // BEZ TP - použijeme trailing
            request.sl = request.price + recovery_sl_distance;
        }
        
        m_logger.LogInfo("📋 RECOVERY ORDER: " + (recovery_pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL") + 
            " " + DoubleToString(recovery_lot, 2) + " lots at " + DoubleToString(request.price, 5) + 
            ", SL=" + DoubleToString(request.sl, 5) + " (no TP - using trailing)");
            
        if(OrderSend(request, result))
        {
            m_logger.LogInfo("💰 RECOVERY TRADE OPENED: " + symbol + " " + (recovery_pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL") + 
                " " + DoubleToString(recovery_lot, 2) + " lots - Using trailing SL (no fixed TP)");
        }
        else
        {
            m_logger.LogError("RECOVERY TRADE FAILED: " + symbol + " - Error: " + IntegerToString(result.retcode));
        }
    }
    
    void ManageHybridTrailing()
    {
        // Projít všechny otevřené pozice a zkontrolovat trailing
        int total_positions = PositionsTotal();
        
        // DEBUG: Log že trailing běží
        static datetime last_debug = 0;
        if(TimeCurrent() - last_debug >= 10) { // každých 10 sekund
            m_logger.LogInfo("🔄 HYBRID TRAILING: Processing " + IntegerToString(total_positions) + " positions");
            last_debug = TimeCurrent();
        }
        
        for(int i = 0; i < total_positions; i++)
        {
            if(!PositionSelectByTicket(PositionGetTicket(i)))
                continue;
            
            // Kontrola, zda pozice patří našemu EA
            if(PositionGetInteger(POSITION_MAGIC) != m_settings.Scalping_MagicNumber)
                continue;
                
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            string position_comment = PositionGetString(POSITION_COMMENT);
            
            // Zkontrolovat, zda se jedná o recovery pozici
            bool is_recovery_position = (StringFind(position_comment, "Recovery_Trade") >= 0);
            
            if(is_recovery_position)
            {
                // Recovery trailing logic - čekat na pokrytí ztráty, pak trailit
                ManageRecoveryTrailing(symbol, ticket, pos_type, open_price, current_sl, position_comment, 0.0);
            }
            else
            {
                // Politika bez TP: pokud TP existuje, ihned jej odstranit a pokračovat v trailingu
                if(current_tp > 0)
                {
                    MqlTradeRequest remove_tp = {};
                    MqlTradeResult remove_res = {};
                    remove_tp.action = TRADE_ACTION_SLTP;
                    remove_tp.position = ticket;
                    remove_tp.symbol = symbol;
                    remove_tp.sl = current_sl;
                    remove_tp.tp = 0; // odstranit TP
                    bool order_result = OrderSend(remove_tp, remove_res);
                    if(!order_result || remove_res.retcode != TRADE_RETCODE_DONE)
                    {
                        m_logger.LogError("❌ Failed to remove TP: " + symbol + " Error:" + IntegerToString(remove_res.retcode));
                    }
                }
                // Pokračovat v čistém trailingu bez TP
                ContinueTrailing(symbol, ticket, pos_type, open_price, current_sl);
            }
        }
    }
    
    void ManageRecoveryTrailing(string symbol, ulong ticket, ENUM_POSITION_TYPE pos_type, double open_price, double current_sl, string position_comment, double original_loss_usd = 5.0)
    {
        // Throttling per pozice - kontrolovat jen každou sekundu
        static datetime last_check_time[];
        static ulong last_check_tickets[];
        
        datetime current_time = TimeCurrent();
        
        // Najít nebo vytvořit záznam pro tuto pozici
        int pos_index = -1;
        for(int i = 0; i < ArraySize(last_check_tickets); i++)
        {
            if(last_check_tickets[i] == ticket)
            {
                pos_index = i;
                break;
            }
        }
        
        // Pokud pozice není v seznamu, přidat ji
        if(pos_index == -1)
        {
            pos_index = ArraySize(last_check_tickets);
            ArrayResize(last_check_tickets, pos_index + 1);
            ArrayResize(last_check_time, pos_index + 1);
            last_check_tickets[pos_index] = ticket;
            last_check_time[pos_index] = 0;
        }
        
        // Throttling pro tuto konkrétní pozici
        if(current_time - last_check_time[pos_index] < 1) {
            return; // Skip pokud jsme kontrolovali tuto pozici nedávno
        }
        last_check_time[pos_index] = current_time;
        
        // DEBUG: Kontrola recovery pozice
        m_logger.LogInfo("🔍 RECOVERY TRAILING CHECK: " + symbol + " #" + IntegerToString(ticket) + 
            ", Comment: " + position_comment);
            
        // Extrapolovat původní ticket a ztrátu z komentáře
        // Formát: "Recovery_Trade_#123_$5.50"
        int hash_pos = StringFind(position_comment, "#");
        int dollar_pos = StringFind(position_comment, "_$");
        if(hash_pos < 0 || dollar_pos < 0) 
        {
            m_logger.LogInfo("❌ Invalid comment format: " + position_comment);
            return;
        }
        
        string original_ticket_str = StringSubstr(position_comment, hash_pos + 1, dollar_pos - hash_pos - 1);
        string original_loss_str = StringSubstr(position_comment, dollar_pos + 2);
        ulong original_ticket = StringToInteger(original_ticket_str);
        double parsed_loss = StringToDouble(original_loss_str);
        
        // Použít parsovanou ztrátu místo default parametru
        if(parsed_loss > 0) {
            original_loss_usd = parsed_loss;
        }
        
        m_logger.LogInfo("📊 PARSED: Ticket=" + IntegerToString(original_ticket) + 
            ", Loss=$" + DoubleToString(original_loss_usd, 2));
        
        // Spočítat současný profit - použít aktuální P&L z pozice
        double current_profit = PositionGetDouble(POSITION_PROFIT);
        
        // Backup výpočet pro kontrolu
        double current_price = (pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double profit_points = (pos_type == POSITION_TYPE_BUY) ? 
            (current_price - open_price) : (open_price - current_price);
        double point_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double calculated_profit = profit_points * point_value * volume;
        
        // OPRAVA: Rozumný breakeven target pro malé ztráty
        double min_target = MathMax(0.05, original_loss_usd * 0.5); // Min $0.05 nebo 50% původní ztráty
        double target_breakeven = original_loss_usd + min_target;
        
        m_logger.LogInfo("💰 RECOVERY PROFIT: $" + DoubleToString(current_profit, 2) + 
            " (target: $" + DoubleToString(target_breakeven, 2) + ")");
        
        // DEBUG: Podrobné info o výpočtu
        m_logger.LogInfo("🔍 PROFIT CALC: ActualProfit=$" + DoubleToString(current_profit, 2) + 
            ", CalculatedProfit=$" + DoubleToString(calculated_profit, 2) + 
            ", ProfitPoints=" + DoubleToString(profit_points, 5) + 
            ", Volume=" + DoubleToString(volume, 2));
        
        // Detekce trendu pro adaptivní trailing
        bool is_strong_trend = IsInStrongTrend(symbol, pos_type);
        
        // Spočítat minimální profit pro začátek trailing (breakeven + trail start pips)
        double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        {
            pip_value *= 10;
        }
        
        // Adaptivní trail start podle trendu
        int effective_trail_start = is_strong_trend ? 
            (m_settings.RecoveryTrailStartPips * 2) :  // Méně agresivní při trendu
            m_settings.RecoveryTrailStartPips;         // Normální při konsolidaci
            
        // OPRAVA: Zjednodušený a omezený trail start pro malé pozice
        double trail_start_usd = effective_trail_start * pip_value * volume * 10.0; // Zjednodušený výpočet
        trail_start_usd = MathMin(trail_start_usd, original_loss_usd * 2.0); // Max 2x původní ztráta
        trail_start_usd = MathMax(trail_start_usd, 0.10); // Min $0.10
        trail_start_usd = MathMin(trail_start_usd, 1.0); // Max $1.00 pro malé pozice
        
        double minimum_profit_for_trail = target_breakeven + trail_start_usd;
        
        // Pokud profit >= minimum_profit_for_trail, začít trailing
        if(current_profit >= minimum_profit_for_trail)
        {
            m_logger.LogInfo("🚀 RECOVERY TRAILING ACTIVATED: Profit $" + DoubleToString(current_profit, 2) + 
                " >= MinTarget $" + DoubleToString(minimum_profit_for_trail, 2) + 
                " (breakeven: $" + DoubleToString(target_breakeven, 2) + " + start: $" + DoubleToString(trail_start_usd, 2) + ")");
            
            // Adaptivní trail step podle trendu
            int effective_trail_step = is_strong_trend ? 
                (m_settings.RecoveryTrailStepPips * 2) :  // Větší vzdálenost při trendu
                m_settings.RecoveryTrailStepPips;         // Normální při konsolidaci
                
            double trail_step = effective_trail_step * pip_value;
            double new_sl;
            
            if(pos_type == POSITION_TYPE_BUY)
            {
                // Pro BUY: SL se posunuje jen nahoru, ale nikdy pod entry cenu
                double potential_sl = current_price - trail_step;
                new_sl = MathMax(current_sl, potential_sl);
                
                // Bezpečnostní kontrola: SL nikdy pod entry cenou
                double min_allowed_sl = open_price; // Pro BUY minimálně na entry
                new_sl = MathMax(new_sl, min_allowed_sl);
                
                m_logger.LogInfo("📈 BUY TRAIL CALC: CurrentPrice=" + DoubleToString(current_price, 5) + 
                    ", PotentialSL=" + DoubleToString(potential_sl, 5) + ", CurrentSL=" + DoubleToString(current_sl, 5) + 
                    ", NewSL=" + DoubleToString(new_sl, 5));
                if(new_sl > current_sl) // Pouze pokud je lepší než současný SL
                {
                    m_logger.LogInfo("📈 BUY TRAIL: Moving SL from " + DoubleToString(current_sl, 5) + 
                        " to " + DoubleToString(new_sl, 5));
                    UpdateRecoverySL(symbol, ticket, new_sl);
                }
                else
                {
                    m_logger.LogInfo("⏸️ SL not updated (new SL not better)");
                }
            }
            else
            {
                // Pro SELL: SL se posunuje jen dolů, ale nikdy nad entry cenu
                double potential_sl = current_price + trail_step;
                new_sl = MathMin(current_sl, potential_sl);
                
                // Bezpečnostní kontrola: SL nikdy nad entry cenou
                double max_allowed_sl = open_price; // Pro SELL maximálně na entry
                new_sl = MathMin(new_sl, max_allowed_sl);
                
                m_logger.LogInfo("📉 SELL TRAIL CALC: CurrentPrice=" + DoubleToString(current_price, 5) + 
                    ", PotentialSL=" + DoubleToString(potential_sl, 5) + ", CurrentSL=" + DoubleToString(current_sl, 5) + 
                    ", NewSL=" + DoubleToString(new_sl, 5));
                if(new_sl < current_sl) // Pouze pokud je lepší než současný SL
                {
                    m_logger.LogInfo("📉 SELL TRAIL: Moving SL from " + DoubleToString(current_sl, 5) + 
                        " to " + DoubleToString(new_sl, 5));
                    UpdateRecoverySL(symbol, ticket, new_sl);
                }
                else
                {
                    m_logger.LogInfo("⏸️ SL not updated (new SL not better)");
                }
            }
        }
        else
        {
            m_logger.LogInfo("⏸️ Waiting for trail start: $" + DoubleToString(current_profit, 2) + 
                " < $" + DoubleToString(minimum_profit_for_trail, 2) + 
                " (need breakeven + " + IntegerToString(m_settings.RecoveryTrailStartPips) + " pips)");
        }
    }
    

    

    
    double GetCurrentPrice(string symbol, ENUM_POSITION_TYPE type)
    {
        return (type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    }
    
    double GetPreviousPrice(string symbol, int bars_back)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, bars_back + 1, rates) < bars_back + 1)
            return 0;
        return rates[bars_back].close;
    }
    

    

    

    

    

    

    

    



    


    bool IsInStrongTrend(string symbol, ENUM_POSITION_TYPE pos_type)
    {
        // Získat posledních 10 svíček
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 10, rates) < 10)
            return false;
            
        // Počet consecutive svíček ve směru pozice
        int consecutive_candles = 0;
        bool trend_direction = (pos_type == POSITION_TYPE_BUY); // true = up, false = down
        
        for(int i = 1; i < 6; i++) // kontrola posledních 5 svíček
        {
            bool candle_bullish = (rates[i].close > rates[i].open);
            if(candle_bullish == trend_direction)
                consecutive_candles++;
            else
                break;
        }
        
        // Pokud 4+ svíček ve směru pozice = silný trend
        bool has_momentum = (consecutive_candles >= 4);
        
        // Volatilita check - vysoká volatilita = trend
        double range_sum = 0;
        for(int i = 1; i < 6; i++)
        {
            range_sum += (rates[i].high - rates[i].low);
        }
        double avg_range = range_sum / 5;
        double recent_range = rates[1].high - rates[1].low;
        bool high_volatility = (recent_range > avg_range * 1.5);
        
        return (has_momentum && high_volatility);
    }

    void UpdateRecoverySL(string symbol, ulong ticket, double new_sl)
    {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = new_sl;
        request.tp = 0; // Recovery pozice nemají TP
        
        m_logger.LogInfo("🔧 TRYING UPDATE SL: " + symbol + " #" + IntegerToString(ticket) + 
            " to " + DoubleToString(new_sl, 5));
        
        if(OrderSend(request, result))
        {
            m_logger.LogInfo("✅ RECOVERY TRAIL SUCCESS: " + symbol + " SL updated to " + DoubleToString(new_sl, 5));
        }
        else
        {
            m_logger.LogInfo("❌ RECOVERY TRAIL FAILED: " + symbol + " Error: " + 
                IntegerToString(result.retcode) + " - " + result.comment);
        }
    }
    
    void CheckTPReachedAndActivateTrailing(string symbol, ulong ticket, ENUM_POSITION_TYPE pos_type, double current_tp)
    {
        double current_price = (pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : 
            SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        bool tp_reached = false;
        
        if(pos_type == POSITION_TYPE_BUY && current_price >= current_tp)
        {
            tp_reached = true;
        }
        else if(pos_type == POSITION_TYPE_SELL && current_price <= current_tp)
        {
            tp_reached = true;
        }
        
        if(tp_reached)
        {
            // TP bylo dosaženo - aktivovat trailing
            ActivateTrailingAfterTP(symbol, ticket, pos_type);
        }
    }
    
    void ActivateTrailingAfterTP(string symbol, ulong ticket, ENUM_POSITION_TYPE pos_type)
    {
        double current_price = (pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : 
            SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        // Vypočítat počáteční trailing SL
        double pip_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        {
            pip_size *= 10;
        }
        
        double lock_distance = m_settings.Scalping_TrailLockPips * pip_size;
        double new_sl = 0;
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            new_sl = current_price - lock_distance;
        }
        else
        {
            new_sl = current_price + lock_distance;
        }
        
        // Normalize SL
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        new_sl = NormalizeDouble(new_sl, digits);
        
        // Poslat modifikaci: odstranit TP, nastavit nový SL
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = new_sl;
        request.tp = 0; // Odstranit TP
        
        m_logger.LogInfo("🔧 ACTIVATING TRAIL: " + symbol + " #" + IntegerToString(ticket) + 
            " removing TP, setting SL to " + DoubleToString(new_sl, 5));
        
        if(OrderSend(request, result))
        {
            m_logger.LogInfo("✅ TRAIL ACTIVATED: " + symbol + " TP removed, SL set to " + DoubleToString(new_sl, 5));
        }
        else
        {
            m_logger.LogInfo("❌ TRAIL ACTIVATION FAILED: " + symbol + " Error: " + 
                IntegerToString(result.retcode) + " - " + result.comment);
        }
    }
    
    void ContinueTrailing(string symbol, ulong ticket, ENUM_POSITION_TYPE pos_type, double open_price, double current_sl)
    {
        double current_price = (pos_type == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : 
            SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        double pip_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        {
            pip_size *= 10;
        }
        
        double trail_step = m_settings.Scalping_TrailStepPips * pip_size;
        double lock_distance = m_settings.Scalping_TrailLockPips * pip_size;
        
        double new_sl = current_sl;
        bool should_update = false;
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            // BUY: Posouvat SL nahoru pokud se cena posunula výše
            double potential_sl = current_price - lock_distance;
            
            // SL se posune jen pokud je nový SL výše než současný + trail_step
            if(potential_sl > current_sl + trail_step)
            {
                // Bezpečnostní pojistka: SL nikdy pod entry cenou
                new_sl = MathMax(potential_sl, open_price);
                should_update = true;
            }
        }
        else
        {
            // SELL: Posouvat SL dolů pokud se cena posunula níže
            double potential_sl = current_price + lock_distance;
            
            // SL se posune jen pokud je nový SL níže než současný - trail_step
            if(potential_sl < current_sl - trail_step)
            {
                // Bezpečnostní pojistka: SL nikdy nad entry cenou
                new_sl = MathMin(potential_sl, open_price);
                should_update = true;
            }
        }
        
        if(should_update)
        {
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            new_sl = NormalizeDouble(new_sl, digits);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = symbol;
            request.sl = new_sl;
            request.tp = 0; // Zachovat bez TP
            
            m_logger.LogInfo("🔧 TRYING TRAIL SL: " + symbol + " #" + IntegerToString(ticket) + 
                " to " + DoubleToString(new_sl, 5));
            
            if(OrderSend(request, result))
            {
                m_logger.LogInfo("✅ TRAIL SUCCESS: " + symbol + " SL updated to " + DoubleToString(new_sl, 5));
            }
            else
            {
                m_logger.LogInfo("❌ TRAIL FAILED: " + symbol + " Error: " + 
                    IntegerToString(result.retcode) + " - " + result.comment);
            }
        }
    }
    
    void CheckScalpingEntries()
    {
        // Zkontrolovat, kolik pozic už máme otevřených
        int current_positions = GetOpenScalpingPositionsCount();
        
        if(current_positions >= m_settings.Scalping_MaxPositions)
        {
            return;
        }
        
        // Early warning je nyní implementováno přímo ve scoring systému
        
        // Zkontrolovat všechny symboly
        
        for(int i = 0; i < m_total_symbols; i++)
        {
            string symbol = m_symbols[i];
            
            // Omezení na jednu pozici na symbol
            if(HasOpenPositionForSymbol(symbol))
                continue;
                
            // Zkontrolovat, zda už byla pozice otevřena na této svíčce
            if(WasPositionOpenedThisCandle(symbol))
                continue;
                
            // Získat skóre symbolu
            double score = m_filter.GetSymbolScore(symbol);
            if(score < m_settings.Scalping_MinScore)
                continue;
            
            // Získat signál (stejná logika jako ConsolidationTRex)
            ENUM_SIGNAL_DIRECTION signal = m_filter.GetCombinedSignal(symbol);
            
            if(signal == SIGNAL_NONE) 
            {
                continue;
            }
            
            // Zkontrolovat KC Squeeze filtr
            if(m_settings.UseKCSqueezeFilter && !m_filter.IsInKCSqueeze(symbol))
            {
                continue;
            }
            
            // Vypnuto: kontrola minimální TP vzdálenosti (jedeme bez TP, exit přes trailing)

            // Otevřít pozici
            OpenScalpingPosition(symbol, signal, score);
            
            // Zaznamenat, že byla pozice otevřena na této svíčce
            MarkPositionOpenedThisCandle(symbol);
            
            // Pouze jedna pozice na tick
            break;
        }
    }
    
    bool IsConsolidationEnding()
    {
        // Analyzovat signály konce konsolidace napříč všemi symboly
        int symbols_in_warning = 0;
        int symbols_with_bb_expansion = 0;
        double total_score = 0;
        int valid_symbols = 0;
        
        for(int i = 0; i < m_total_symbols; i++)
            {
                string symbol = m_symbols[i];
                double score = m_filter.GetSymbolScore(symbol);
            
            // Počítat pouze symboly s relevantním score
            if(score > 30.0) // Ignorovat úplně mrtvé symboly
            {
                total_score += score;
                valid_symbols++;
                
                // Signál 1: Score v warning zóně
                if(score < m_settings.WarningThreshold)
                {
                    symbols_in_warning++;
                }
                
                // Signál 2: BB expansion
                if(m_filter.IsBBExpanding(symbol))
                {
                    symbols_with_bb_expansion++;
                }
            }
        }
        
        if(valid_symbols == 0) return false;
        
        double average_score = total_score / valid_symbols;
        double warning_ratio = (double)symbols_in_warning / valid_symbols;
        double expansion_ratio = (double)symbols_with_bb_expansion / valid_symbols;
        
        // Early warning kritéria
        bool score_warning = (average_score < m_settings.WarningThreshold);
        bool majority_warning = (warning_ratio > 0.5); // Více než 50% symbolů
        bool expansion_detected = (expansion_ratio > 0.3); // 30%+ symbolů má BB expansion
        
        if(score_warning || majority_warning || expansion_detected)
        {

            return true;
        }
        
        return false;
    }
    
    void UpdateDashboard()
    {
        // Připravit data pro dashboard
        SSignalInfo all_signal_info[];
        ArrayResize(all_signal_info, m_total_symbols);

        for(int i = 0; i < m_total_symbols; i++)
        {
            string symbol = m_symbols[i];
            all_signal_info[i].symbol = symbol;
            all_signal_info[i].score = m_filter.GetSymbolScore(symbol);
            all_signal_info[i].final_signal = m_filter.GetCombinedSignal(symbol);
            all_signal_info[i].rsi_signal = m_filter.GetRsiSignal(symbol);
            all_signal_info[i].bb_signal = m_filter.GetBollingerSignal(symbol);
            all_signal_info[i].stoch_signal = m_filter.GetStochasticSignal(symbol);
            all_signal_info[i].grid_status = GRID_NONE; // Scalping nepoužívá grid
            
            // Získat stav pozice
            all_signal_info[i].has_position = HasOpenPositionForSymbol(symbol);
        }
        
        // Aktualizovat dashboard (předat pouze data)
        SMarketStatusInfo dummy_status;
        dummy_status.text = "";
        dummy_status.text_color = clrWhite;
        m_dashboard.Update(m_settings, all_signal_info, dummy_status);
    }

    bool ParseSymbols()
    {
        string symbol_string = m_settings.SymbolsToTrade;
        string symbol_array[];
        int count = StringSplit(symbol_string, ',', symbol_array);
        
        if(count <= 0)
        {
            m_logger.LogError("ParseSymbols: Nebyl nalezen žádný symbol k parsování");
            return false;
        }
        
        // Připravit pole symbolů
        ArrayResize(m_symbols, count);
        m_total_symbols = 0;
        
        for(int i = 0; i < count; i++)
        {
            string symbol = symbol_array[i];
            StringTrimLeft(symbol);
            StringTrimRight(symbol);
            
            if(StringLen(symbol) > 0)
            {
                ValidateAndAddSymbol(symbol);
            }
        }
        
        if(m_total_symbols == 0)
        {
            m_logger.LogError("ParseSymbols: Žádný validní symbol nebyl přidán");
            return false;
        }
        
        // Resize pole na skutečný počet symbolů
        ArrayResize(m_symbols, m_total_symbols);
        return true;
    }

    void ValidateAndAddSymbol(string symbol_to_validate)
    {
        bool symbol_exists = false;
        
        // Test, zda existuje symbol na trhu
        double test_bid = SymbolInfoDouble(symbol_to_validate, SYMBOL_BID);
        double test_ask = SymbolInfoDouble(symbol_to_validate, SYMBOL_ASK);
        
        if(test_bid > 0 && test_ask > 0)
        {
            symbol_exists = true;
            }
            else
            {
            // Pokusit se přidat symbol do MarketWatch
            if(SymbolSelect(symbol_to_validate, true))
            {
                Sleep(100); // Krátká pauza pro načtení dat
                test_bid = SymbolInfoDouble(symbol_to_validate, SYMBOL_BID);
                test_ask = SymbolInfoDouble(symbol_to_validate, SYMBOL_ASK);
                
                if(test_bid > 0 && test_ask > 0)
                {
                    symbol_exists = true;
                }
            }
        }
        
        if(symbol_exists)
        {
            m_symbols[m_total_symbols] = symbol_to_validate;
            m_total_symbols++;

        }
        else
        {
            m_logger.LogWarning("ParseSymbols: Symbol " + symbol_to_validate + " není dostupný a nebude obchodován");
        }
    }

    void OpenScalpingPosition(string symbol, ENUM_SIGNAL_DIRECTION signal, double score)
    {
        // Získat Bollinger Bands pro výpočet SL a TP
        double bb_upper, bb_lower;
        if(!GetBollingerBands(symbol, bb_upper, bb_lower))
        {
            m_logger.LogError("OpenScalpingPosition: Nelze získat Bollinger Bands pro " + symbol);
            return;
        }
        
        bool is_buy = (signal == SIGNAL_BUY);
        
        // Vypočítat TP a SL
        double tp_price = CalculateScalpingTP(symbol, bb_upper, bb_lower, is_buy);
        
        double entry_price = is_buy ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : 
            SymbolInfoDouble(symbol, SYMBOL_BID);
            
        double sl_price = CalculateScalpingSL(symbol, bb_upper, bb_lower, is_buy, tp_price, entry_price);
        
        // Vytvorit trade request
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = symbol;
        request.volume = m_settings.Scalping_FixedLot;
        request.type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.price = entry_price;
        request.sl = sl_price;
        request.tp = 0; // Bez TP – exit řídí trailing
        request.magic = m_settings.Scalping_MagicNumber;
        request.comment = "Scalping_" + EnumToString(signal) + "_" + DoubleToString(score, 1);
        
        if(OrderSend(request, result))
        {

        }
        else
        {
            m_logger.LogError("OpenScalpingPosition: Chyba při otevírání pozice pro " + symbol + ", error: " + IntegerToString(result.retcode));
        }
    }
    
    double CalculateScalpingSL(string symbol, double bb_upper, double bb_lower, bool is_buy, double tp_price, double entry_price)
    {
        // SL na základě Risk-Reward Ratio
        double tp_distance = MathAbs(tp_price - entry_price);
        double sl_distance = tp_distance / m_settings.Scalping_RiskRewardRatio;
        
        double sl_price = 0;
        if(is_buy)
        {
            sl_price = entry_price - sl_distance;
        }
        else
        {
            sl_price = entry_price + sl_distance;
        }
        
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        return NormalizeDouble(sl_price, digits);
    }
    
    double CalculateScalpingTP(string symbol, double bb_upper, double bb_lower, bool is_buy)
    {
        double current_price = is_buy ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : 
            SymbolInfoDouble(symbol, SYMBOL_BID);
            
        double tp_price = 0;
        if(is_buy)
        {
            // BUY pozice: TP na 40% cesty k horní BB hranici
            double distance_to_upper = bb_upper - current_price;
            tp_price = current_price + (distance_to_upper * 0.4);
        }
        else
        {
            // SELL pozice: TP na 40% cesty ke spodní BB hranici
            double distance_to_lower = current_price - bb_lower;  
            tp_price = current_price - (distance_to_lower * 0.4);
        }
        
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        return tp_price;
    }
    
    bool GetBollingerBands(string symbol, double &upper, double &lower)
    {
        int bb_handle = iBands(symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE)
        {
            return false;
        }
        
        double upper_buffer[], lower_buffer[];
        ArraySetAsSeries(upper_buffer, true);
        ArraySetAsSeries(lower_buffer, true);
        
        if(CopyBuffer(bb_handle, 1, 0, 1, upper_buffer) < 1 ||
           CopyBuffer(bb_handle, 2, 0, 1, lower_buffer) < 1)
        {
            IndicatorRelease(bb_handle);
            return false;
        }
        
        upper = upper_buffer[0]; // Aktuální svíčka pro scalping
        lower = lower_buffer[0]; // Aktuální svíčka pro scalping
        IndicatorRelease(bb_handle);
        return true;
    }
    
    void RemoveAllSubcharts()
    {
        long total = ChartGetInteger(0, CHART_WINDOWS_TOTAL);

        
        // Procházíme všechna okna od posledního k prvnímu
        for(int w = (int)total-1; w > 0; w--) // w = 0 je hlavní okno
        {
            int indicators_before = (int)ChartIndicatorsTotal(0, w);
            while(ChartIndicatorsTotal(0, w) > 0)
            {
                ChartIndicatorDelete(0, w, (string)0);
            }
            int indicators_after = (int)ChartIndicatorsTotal(0, w);
            if(indicators_before > 0)
            {

            }
        }

    }
    
    bool HasOpenPositionForSymbol(string symbol)
    {
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol && 
                   PositionGetInteger(POSITION_MAGIC) == m_settings.Scalping_MagicNumber)
                {
                    return true;
                }
            }
        }
        return false;
    }
    
    bool WasPositionOpenedThisCandle(string symbol)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 1, rates) < 1)
            return false;
            
        string current_candle_time = TimeToString(rates[0].time);
        
        // Najít záznam pro tento symbol
        for(int i = 0; i < ArraySize(last_processed_candle_time); i += 2)
        {
            if(i + 1 < ArraySize(last_processed_candle_time))
            {
                if(last_processed_candle_time[i] == symbol)
                {
                    return (last_processed_candle_time[i + 1] == current_candle_time);
                }
            }
        }
        
        return false;
    }
    
    void MarkPositionOpenedThisCandle(string symbol)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        
        if(CopyRates(symbol, PERIOD_CURRENT, 0, 1, rates) < 1)
            return;
            
        string current_candle_time = TimeToString(rates[0].time);
        
        // Najít existující záznam nebo vytvořit nový
        int found_index = -1;
        for(int i = 0; i < ArraySize(last_processed_candle_time); i += 2)
        {
            if(i + 1 < ArraySize(last_processed_candle_time))
            {
                if(last_processed_candle_time[i] == symbol)
                {
                    found_index = i;
                    break;
                }
            }
        }
        
        if(found_index >= 0)
        {
            // Aktualizovat existující záznam
            last_processed_candle_time[found_index + 1] = current_candle_time;
        }
        else
        {
            // Přidat nový záznam
            int current_size = ArraySize(last_processed_candle_time);
            ArrayResize(last_processed_candle_time, current_size + 2);
            last_processed_candle_time[current_size] = symbol;
            last_processed_candle_time[current_size + 1] = current_candle_time;
        }
    }
};

// Statická definice - odstraněno kvůli chybě, používáme instanční member
