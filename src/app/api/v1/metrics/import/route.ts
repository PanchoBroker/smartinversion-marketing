import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export async function POST(req: Request) {
  try {
    // 1. Validación de Variables de Entorno (Crítico para S6-003)
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      console.error('Missing Supabase environment variables');
      return NextResponse.json({ 
        error: 'Server configuration error: Missing Supabase credentials' 
      }, { status: 500 });
    }

    // 2. Inicialización del Cliente
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 3. Parseo y validación del cuerpo
    const body = await req.json();
    const { provider, publication_id, window, payload } = body;

    if (!provider || !publication_id || !window || !payload) {
      return NextResponse.json({ 
        error: 'Missing required fields', 
        required: ['provider', 'publication_id', 'window', 'payload'] 
      }, { status: 400 });
    }

    // 4. Inserción en metric_snapshots
    const { data, error } = await supabase
      .from('metric_snapshots')
      .insert([
        {
          provider,
          publication_id,
          window,
          payload, // JSONB
          imported_at: new Date().toISOString(),
        }
      ])
      .select()
      .single();

    if (error) {
      console.error('Supabase insert error:', error);
      return NextResponse.json({ 
        error: 'Database insertion failed', 
        details: error.message 
      }, { status: 500 });
    }

    // 5. Respuesta exitosa estandarizada
    return NextResponse.json({
      success: true,
      data: {
        id: data.id,
        message: 'Metric snapshot imported successfully'
      }
    }, { status: 201 });

  } catch (err) {
    console.error('API Route Error:', err);
    return NextResponse.json({ 
      error: 'Internal Server Error' 
    }, { status: 500 });
  }
}