//+------------------------------------------------------------------+
//|                                                  TradeManager.mqh|
//|                        Copyright 2024, Tomas Nezval              |
//|                                             https://www.nezval.cz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Tomas Nezval"
#property link      "https://www.nezval.cz"

#include <Trade/Trade.mqh>
#include "Logger.mqh"

class CTradeManager
{
private:
    CTrade             m_trade;
    CLogger*           m_logger;
    int                m_magic_number;

public:
    void Initialize(CLogger* logger, int magic_number)
    {
        m_logger = logger;
        m_magic_number = magic_number;
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetMarginMode();
    }

    bool PositionOpen(const string symbol, ENUM_ORDER_TYPE order_type, double volume, double price, double sl, double tp, const string comment)
    {
        MqlTradeRequest request;
        ZeroMemory(request);
        MqlTradeResult  result  = {0};

        request.action   = TRADE_ACTION_DEAL;
        request.symbol   = symbol;
        request.volume   = volume;
        request.type     = order_type;
        request.price    = price;
        request.sl       = sl;
        request.tp       = tp;
        request.magic    = m_magic_number;
        request.comment  = comment;
        request.type_filling = ORDER_FILLING_FOK;

        if(!OrderSend(request, result))
        {
            m_logger.LogError("OrderSend failed for " + symbol + ". Error: " + IntegerToString(GetLastError()));
            return false;
        }
        
        m_logger.LogInfo("Position opened: " + symbol + " " + EnumToString(order_type) + " " + DoubleToString(volume) + " @ " + DoubleToString(price, 5) + ", SL: " + DoubleToString(sl, 5));
        return true;
    }
    
    bool PositionModify(ulong ticket, double sl, double tp)
    {
        if(!m_trade.PositionModify(ticket, sl, tp))
        {
             m_logger.LogError("PositionModify failed for ticket " + (string)ticket + ". Error: " + IntegerToString(GetLastError()));
             return false;
        }
        m_logger.LogInfo("Position modified: ticket " + (string)ticket + ", new SL: " + DoubleToString(sl, 5));
        return true;
    }
    
    bool ClosePosition(ulong ticket, const string reason = "")
    {
        if(!m_trade.PositionClose(ticket))
        {
            m_logger.LogError("ClosePosition failed for ticket " + (string)ticket + ". Error: " + IntegerToString(GetLastError()));
            return false;
        }
        m_logger.LogInfo("Position closed: ticket " + (string)ticket + " - " + reason);
        return true;
    }
    
    bool IsPositionOpen(const string symbol)
    {
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == m_magic_number)
                {
                    return true;
                }
            }
        }
        return false;
    }
};


