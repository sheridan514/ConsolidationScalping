//+------------------------------------------------------------------+
//|                                                      Logger.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Enum pro úrovně logování                                        |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
    LOG_ERROR   = 0,  // Pouze chyby
    LOG_WARNING = 1,  // Chyby + varování
    LOG_INFO    = 2,  // Chyby + varování + info
    LOG_DEBUG   = 3   // Všechny zprávy včetně debug
};

//+------------------------------------------------------------------+
//| Třída pro centralizované logování                               |
//+------------------------------------------------------------------+
class CLogger
{
private:
    string m_system_name;
    static ENUM_LOG_LEVEL m_log_level;  // Statická proměnná pro všechny instance
    
public:
    //--- Konstruktor
    CLogger(string system_name = "ConsolidationScalping")
    {
        m_system_name = system_name;
    }
    
    //--- Inicializace (kompatibilita)
    void Initialize(string log_name = "")
    {
        // Logger je už inicializován konstruktorem
        if(log_name != "") m_system_name = log_name;
        
        // Nastavit debug level aby se zobrazovaly všechny zprávy
        SetLogLevel(LOG_DEBUG);
    }
    
    //--- Nastavení úrovně logování pro všechny loggery
    static void SetLogLevel(ENUM_LOG_LEVEL level)
    {
        m_log_level = level;
    }
    
    //--- Logovací metody s úrovní kontroly
    void LogInfo(string message)
    {
        if(m_log_level >= LOG_INFO)
            Print(m_system_name + ": " + message);
    }
    
    void LogWarning(string message)
    {
        if(m_log_level >= LOG_WARNING)
            Print(m_system_name + " WARNING: " + message);
    }
    
    void LogError(string message)
    {
        if(m_log_level >= LOG_ERROR)
            Print(m_system_name + " ERROR: " + message);
    }
    
    void LogDebug(string message)
    {
        if(m_log_level >= LOG_DEBUG)
            Print(m_system_name + " DEBUG: " + message);
    }
};

// Inicializace statické proměnné
static ENUM_LOG_LEVEL CLogger::m_log_level = LOG_DEBUG;
