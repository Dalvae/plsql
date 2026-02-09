-- pry2206 semana 5 - aporte sbif
-- bloque pl/sql anonimo complejo
-- Diego Alvarez

-- se cambia el formato de fecha para que las fechas se muestren como dd/mm/yyyy
ALTER SESSION SET NLS_DATE_FORMAT = 'DD/MM/YYYY';

-- variable bind para ingresar el periodo de ejecucion de forma parametrica (requisito n)
VARIABLE v_periodo NUMBER
EXEC :v_periodo := EXTRACT(YEAR FROM SYSDATE)

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 50

DECLARE
    -- se define un varray para guardar los codigos de los tipos de transaccion
    -- que se deben procesar: 102 = avance en efectivo, 103 = super avance (requisito k)
    TYPE t_tipos IS VARRAY(2) OF NUMBER(4);
    v_tipos t_tipos := t_tipos(102, 103);

    -- se define un record plsql para guardar los datos de cada transaccion
    -- que se va sacando del cursor de detalle (requisito l)
    TYPE r_detalle IS RECORD (
        numrun              cliente.numrun%TYPE,
        dvrun               cliente.dvrun%TYPE,
        nro_tarjeta         tarjeta_cliente.nro_tarjeta%TYPE,
        nro_transaccion     transaccion_tarjeta_cliente.nro_transaccion%TYPE,
        fecha_transaccion   transaccion_tarjeta_cliente.fecha_transaccion%TYPE,
        monto_total         transaccion_tarjeta_cliente.monto_total_transaccion%TYPE,
        tipo_transaccion    tipo_transaccion_tarjeta.nombre_tptran_tarjeta%TYPE
    );
    v_reg r_detalle;

    -- variable para guardar el año que viene de la variable bind
    v_anio NUMBER := :v_periodo;

    -- variable para guardar el mes que se lee del cursor 1
    v_mes VARCHAR2(6);

    -- variables para los calculos del aporte
    v_porcentaje    NUMBER(2);
    v_aporte        NUMBER(10);

    -- acumuladores para ir sumando montos y aportes del resumen
    v_monto_acum    NUMBER(10);
    v_aporte_acum   NUMBER(10);

    -- variable para guardar el nombre del tipo de transaccion para el resumen
    v_nombre_tipo   tipo_transaccion_tarjeta.nombre_tptran_tarjeta%TYPE;

    -- variables para el contador de iteraciones y validacion (requisito m)
    v_contador      NUMBER := 0;
    v_total         NUMBER := 0;
    v_temp          NUMBER := 0;

    -- cursor 1 (sin parametro): obtiene los meses distintos que tienen
    -- transacciones en el año de la variable bind
    -- el order by se pone aca en el cursor para que los datos salgan ordenados
    CURSOR c_meses IS
        SELECT DISTINCT TO_CHAR(t.fecha_transaccion, 'MMYYYY') AS mes_anno
        FROM transaccion_tarjeta_cliente t
        WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = v_anio
        ORDER BY TO_CHAR(t.fecha_transaccion, 'MMYYYY');

    -- cursor 2 (con parametro): trae las transacciones de un mes y tipo especifico
    -- recibe el mes y el codigo del tipo de transaccion como parametros
    -- ordenado por fecha de transaccion y numrun del cliente (requisito f)
    CURSOR c_detalle(p_mes VARCHAR2, p_tipo NUMBER) IS
        SELECT c.numrun,
               c.dvrun,
               tc.nro_tarjeta,
               t.nro_transaccion,
               t.fecha_transaccion,
               t.monto_total_transaccion,
               tt.nombre_tptran_tarjeta
        FROM transaccion_tarjeta_cliente t
        JOIN tarjeta_cliente tc ON t.nro_tarjeta = tc.nro_tarjeta
        JOIN cliente c ON tc.numrun = c.numrun
        JOIN tipo_transaccion_tarjeta tt
             ON t.cod_tptran_tarjeta = tt.cod_tptran_tarjeta
        WHERE t.cod_tptran_tarjeta = p_tipo
          AND TO_CHAR(t.fecha_transaccion, 'MMYYYY') = p_mes
        ORDER BY t.fecha_transaccion, c.numrun;

    -- excepcion no predefinida: se asocia al error ORA-01438 que ocurre
    -- cuando un valor numerico excede la precision de la columna (requisito j)
    e_precision EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_precision, -1438);

    -- excepcion definida por el usuario: se va a lanzar si el programa
    -- no procesa todas las transacciones esperadas (requisito j)
    e_faltan_registros EXCEPTION;

BEGIN
    -- se truncan las tablas de salida con execute immediate para que se pueda
    -- ejecutar el bloque varias veces sin que se dupliquen datos (requisito g)
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_aporte_sbif';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_aporte_sbif';

    DBMS_OUTPUT.PUT_LINE('=== proceso aporte sbif ===');
    DBMS_OUTPUT.PUT_LINE('anio a procesar: ' || v_anio);

    -- se cuenta cuantas transacciones de avance y super avance hay en el año
    -- para despues comparar con el contador y verificar que se procesaron todas
    FOR i IN 1..v_tipos.COUNT LOOP
        SELECT COUNT(*) INTO v_temp
        FROM transaccion_tarjeta_cliente
        WHERE cod_tptran_tarjeta = v_tipos(i)
          AND EXTRACT(YEAR FROM fecha_transaccion) = v_anio;
        v_total := v_total + v_temp;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('total transacciones esperadas: ' || v_total);

    -- se abre el cursor 1 para recorrer cada mes que tiene transacciones
    OPEN c_meses;
    LOOP
        -- se lee el siguiente mes del cursor 1
        FETCH c_meses INTO v_mes;
        EXIT WHEN c_meses%NOTFOUND;

        -- por cada mes se recorren los tipos de transaccion del varray
        FOR i IN 1..v_tipos.COUNT LOOP
            -- se reinician los acumuladores para este mes y tipo
            v_monto_acum  := 0;
            v_aporte_acum := 0;
            v_nombre_tipo := NULL;

            -- se abre el cursor 2 pasandole el mes y el tipo como parametros
            OPEN c_detalle(v_mes, v_tipos(i));
            LOOP
                -- se lee cada transaccion y se guarda en el record
                FETCH c_detalle INTO v_reg;
                EXIT WHEN c_detalle%NOTFOUND;

                -- se guarda el nombre del tipo para usarlo en el insert del resumen
                v_nombre_tipo := v_reg.tipo_transaccion;

                -- se busca el porcentaje de aporte en la tabla tramo_aporte_sbif
                -- segun el monto de la transaccion (no se hardcodea, se lee de la tabla)
                BEGIN
                    SELECT porc_aporte_sbif INTO v_porcentaje
                    FROM tramo_aporte_sbif
                    WHERE v_reg.monto_total
                          BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;
                EXCEPTION
                    -- excepcion predefinida: no_data_found (requisito j)
                    -- se activa cuando el monto no calza en ningun tramo de la tabla
                    WHEN NO_DATA_FOUND THEN
                        DBMS_OUTPUT.PUT_LINE('aviso: monto ' || v_reg.monto_total
                            || ' no calza en ningun tramo (run: ' || v_reg.numrun || ')');
                        v_porcentaje := 0;
                END;

                -- se calcula el aporte y se redondea a entero sin decimales (requisito h)
                v_aporte := ROUND(v_reg.monto_total * v_porcentaje / 100);

                -- se inserta el registro en la tabla detalle_aporte_sbif
                INSERT INTO detalle_aporte_sbif (
                    numrun, dvrun, nro_tarjeta, nro_transaccion,
                    fecha_transaccion, tipo_transaccion,
                    monto_transaccion, aporte_sbif
                ) VALUES (
                    v_reg.numrun, v_reg.dvrun, v_reg.nro_tarjeta,
                    v_reg.nro_transaccion, v_reg.fecha_transaccion,
                    v_reg.tipo_transaccion, v_reg.monto_total, v_aporte
                );

                -- se van acumulando los montos y aportes para el resumen de este mes/tipo
                v_monto_acum  := v_monto_acum + v_reg.monto_total;
                v_aporte_acum := v_aporte_acum + v_aporte;

                -- se suma 1 al contador para despues verificar que se procesaron todas
                v_contador := v_contador + 1;
            END LOOP;
            -- se cierra el cursor 2 despues de procesar todas las transacciones del mes/tipo
            CLOSE c_detalle;

            -- si se encontraron transacciones para este mes/tipo se inserta el resumen
            IF v_nombre_tipo IS NOT NULL THEN
                INSERT INTO resumen_aporte_sbif (
                    mes_anno, tipo_transaccion,
                    monto_total_transacciones, aporte_total_abif
                ) VALUES (
                    v_mes, v_nombre_tipo,
                    v_monto_acum, v_aporte_acum
                );
            END IF;
        END LOOP;
    END LOOP;
    -- se cierra el cursor 1 despues de recorrer todos los meses
    CLOSE c_meses;

    -- se valida que el contador de registros procesados coincida con el total
    -- esperado. si no coincide se lanza la excepcion definida por el usuario
    IF v_contador != v_total THEN
        RAISE e_faltan_registros;
    END IF;

    -- se confirma la transaccion solo si se procesaron todos los registros (requisito m)
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('proceso completado ok - registros procesados: '
                         || v_contador || ' de ' || v_total);

EXCEPTION
    -- excepcion no predefinida: error ora-01438 cuando un valor excede
    -- la precision de una columna numerica
    WHEN e_precision THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('error: valor excede precision de columna - ' || SQLERRM);

    -- excepcion definida por el usuario: se activa cuando no se procesaron
    -- todas las transacciones esperadas
    WHEN e_faltan_registros THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('error: no se procesaron todos los registros - procesados: '
                             || v_contador || ' de ' || v_total);

    -- cualquier otro error que pueda ocurrir
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('error inesperado: ' || SQLCODE || ' - ' || SQLERRM);
END;
/

-- consultas para mostrar los resultados despues de ejecutar el bloque
PROMPT
PROMPT TABLA DETALLE_APORTE_SBIF
SELECT numrun, dvrun, nro_tarjeta, nro_transaccion,
       TO_CHAR(fecha_transaccion, 'DD/MM/YYYY') AS fecha_transaccion,
       tipo_transaccion, monto_transaccion, aporte_sbif
FROM detalle_aporte_sbif
ORDER BY fecha_transaccion, numrun;

PROMPT
PROMPT TABLA RESUMEN_APORTE_SBIF
SELECT mes_anno, tipo_transaccion,
       monto_total_transacciones, aporte_total_abif
FROM resumen_aporte_sbif
ORDER BY mes_anno, tipo_transaccion;

EXIT;
